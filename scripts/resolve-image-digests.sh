#!/usr/bin/env bash
#
# Resolve every container image tag that Mijn Bureau uses at the pinned
# mijn-bureau-infra revision to its immutable manifest digest (OQ-5).
#
# Reads the FULL image list from upstream
#   helmfile/environments/default/container.yaml.gotmpl
# at the revision recorded in manifest/appliance-manifest.json
# (mijn_bureau.rev), resolves each `registry/repository:tag` with skopeo
# (anonymous, read-only registry access) and writes
#   manifest/image-digests.json
# sorted and deterministic, so a re-run without upstream changes yields an
# identical file except for the `resolved` date.
#
# Per image we record:
#   digest        sha256 of the top-level manifest the tag points at (for a
#                 multi-arch image this is the manifest list / OCI index)
#   amd64_digest  sha256 of the linux/amd64 platform manifest (equal to
#                 `digest` for a single-arch amd64 image)
#   used_by       the key path(s) in container.yaml.gotmpl that reference it
#
# Usage:
#   bash scripts/resolve-image-digests.sh           # refresh the file
#   bash scripts/resolve-image-digests.sh --check   # compare, do not write
#
# --check exits non-zero when the committed file is missing an upstream image,
# lists an image upstream no longer has, or when any digest differs from what
# the registry serves now. A changed digest means the tag was re-pointed
# upstream (the very thing digest pinning exists to catch); review it before
# refreshing the file.
#
# Requires: bash, curl, Python 3 (`python3` or `python`), sha256sum, and
# skopeo. When skopeo is not on
# PATH it is run through `nix shell` from the nixpkgs revision pinned in the
# manifest (override with SKOPEO="..." if needed). Needs network access.
# Never touches the appliance manifest or any disk device.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${REPO_ROOT}/manifest/appliance-manifest.json"
OUT_FILE="${REPO_ROOT}/manifest/image-digests.json"
UPSTREAM_REPO="https://github.com/MinBZK/mijn-bureau-infra"
UPSTREAM_FILE="helmfile/environments/default/container.yaml.gotmpl"

CHECK=0
usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  echo "Options: --check   compare with ${OUT_FILE#"${REPO_ROOT}"/} and exit 1 on any difference"
  echo "         --out F   write to F instead of the default"
  echo "         --help"
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=1 ;;
    --out) shift; OUT_FILE="${1:?--out needs a path}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

for tool in curl sha256sum; do
  command -v "${tool}" >/dev/null 2>&1 || { echo "missing tool: ${tool}" >&2; exit 2; }
done
# Windows Git Bash usually ships `python` (3.x) without a `python3` alias.
PY="$(command -v python3 || command -v python || true)"
if [[ -z "${PY}" ]] || ! "${PY}" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)'; then
  echo "missing tool: python 3 (looked for python3, python)" >&2; exit 2
fi
[[ -f "${MANIFEST}" ]] || { echo "manifest not found: ${MANIFEST}" >&2; exit 2; }

REV="$("${PY}" -c 'import json,sys; print(json.load(open(sys.argv[1]))["mijn_bureau"]["rev"])' "${MANIFEST}")"
NIXPKGS_REV="$("${PY}" -c 'import json,sys; print(json.load(open(sys.argv[1]))["nix"]["nixpkgs"]["rev"])' "${MANIFEST}")"
[[ "${REV}" =~ ^[0-9a-f]{40}$ ]] || { echo "mijn_bureau.rev in manifest is not a full sha1: ${REV}" >&2; exit 2; }

# --- skopeo: PATH, or nix shell from the pinned nixpkgs -----------------------
if [[ -z "${SKOPEO:-}" ]]; then
  if command -v skopeo >/dev/null 2>&1; then
    SKOPEO="skopeo"
  elif command -v nix >/dev/null 2>&1; then
    SKOPEO="nix shell github:NixOS/nixpkgs/${NIXPKGS_REV}#skopeo -c skopeo"
    echo "skopeo not on PATH; using: ${SKOPEO}" >&2
  else
    echo "need skopeo or nix on PATH (or set SKOPEO=...)" >&2
    exit 2
  fi
fi
# shellcheck disable=SC2206  # intentional word splitting of the command string
SKOPEO_CMD=(${SKOPEO})
skopeo() { "${SKOPEO_CMD[@]}" "$@"; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# --- 1. fetch the upstream image list at the pinned rev -----------------------
RAW_URL="https://raw.githubusercontent.com/MinBZK/mijn-bureau-infra/${REV}/${UPSTREAM_FILE}"
echo "fetching ${UPSTREAM_FILE} @ ${REV:0:12}"
curl -fsSL --retry 3 "${RAW_URL}" -o "${WORK}/container.yaml.gotmpl"

# --- 2. parse registry/repository/tag triples ---------------------------------
# The file is YAML with (potentially) Go-template directives. We do not need a
# YAML library: it is a two-to-three-level mapping of scalars. Template lines
# and comments are dropped; `registry` is inherited from the enclosing key
# (openproject/docs/bureaublad set it once and list several images below it).
# Output: one line per reference, "<key.path>\t<registry/repository:tag>".
"${PY}" - "${WORK}/container.yaml.gotmpl" > "${WORK}/refs.tsv" <<'PY'
import re, sys

def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1]
    return v

def normalize_registry(r):
    # Docker Hub has several hostnames; the canonical reference form is docker.io
    if r in ("registry-1.docker.io", "index.docker.io", "docker.io", ""):
        return "docker.io"
    return r

def normalize_repo(registry, repo):
    if registry == "docker.io" and "/" not in repo:
        return "library/" + repo
    return repo

# Build a nested dict from the indentation. Only "key:" and "key: value" lines
# matter; anything templated ({{ ... }}), blank or a comment is skipped.
root = {}
stack = [(-1, root)]
line_re = re.compile(r'^(\s*)([A-Za-z0-9_.-]+):\s*(.*?)\s*$')
for raw in open(sys.argv[1], encoding="utf-8"):
    line = raw.rstrip("\n")
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or stripped.startswith("{{"):
        continue
    m = line_re.match(line)
    if not m:
        continue
    indent, key, value = len(m.group(1)), m.group(2), m.group(3)
    if "{{" in value:
        value = re.sub(r"\{\{.*?\}\}", "", value)
    while stack and stack[-1][0] >= indent:
        stack.pop()
    parent = stack[-1][1]
    if value == "":
        node = {}
        parent[key] = node
        stack.append((indent, node))
    else:
        parent[key] = unquote(value)

def walk(node, path, registry):
    if not isinstance(node, dict):
        return
    reg = node.get("registry", registry)
    if isinstance(reg, str) and reg not in ("~", "null"):
        registry = reg
    repo, tag = node.get("repository"), node.get("tag")
    if isinstance(repo, str) and isinstance(tag, str) and repo and tag and tag not in ("~", "null"):
        r = normalize_registry(registry or "")
        print(f"{'.'.join(path)}\t{r}/{normalize_repo(r, repo)}:{tag}")
    for k, v in node.items():
        if isinstance(v, dict):
            walk(v, path + [k], registry)

container = root.get("container")
if not isinstance(container, dict):
    sys.exit("no top-level 'container:' mapping found in upstream file")
for k, v in container.items():
    walk(v, [k], None)
PY

if [[ ! -s "${WORK}/refs.tsv" ]]; then
  echo "no image references parsed from ${UPSTREAM_FILE}" >&2
  exit 1
fi
cut -f2 "${WORK}/refs.tsv" | sort -u > "${WORK}/images.txt"
n_images="$(wc -l < "${WORK}/images.txt")"
echo "parsed $(wc -l < "${WORK}/refs.tsv") references, ${n_images} unique images"

# --- 3. resolve each image with skopeo ----------------------------------------
# For each image: fetch the raw top-level manifest (its sha256 IS the digest),
# then find the linux/amd64 platform digest: from the index if multi-arch, or
# by confirming the architecture of a single-platform manifest.
# Output: "<image>\t<digest|->\t<amd64_digest|->\t<error>"
: > "${WORK}/resolved.tsv"
ok=0; failed=0
while IFS= read -r image; do
  printf '  %-70s ' "${image}"
  err=""; digest="-"; amd64="-"
  if skopeo inspect --raw "docker://${image}" > "${WORK}/manifest.json" 2> "${WORK}/err.txt"; then
    digest="sha256:$(sha256sum "${WORK}/manifest.json" | awk '{print $1}')"
    # kind: "index" (multi-arch) with the amd64 digest, or "single"
    "${PY}" - "${WORK}/manifest.json" > "${WORK}/kind.txt" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
mt = m.get("mediaType", "")
if "manifests" in m and ("index" in mt or "manifest.list" in mt or not mt):
    for e in m["manifests"]:
        p = e.get("platform") or {}
        if p.get("os") == "linux" and p.get("architecture") == "amd64" and e.get("annotations", {}).get("vnd.docker.reference.type") != "attestation-manifest":
            print("index", e["digest"]); break
    else:
        print("index", "-")
else:
    print("single", "-")
PY
    read -r kind amd64 < "${WORK}/kind.txt"
    if [[ "${kind}" == "single" ]]; then
      # Single-platform manifest: confirm it is linux/amd64 via the config blob.
      arch="$(skopeo inspect --format '{{.Os}}/{{.Architecture}}' "docker://${image}" 2>>"${WORK}/err.txt" || echo "?")"
      if [[ "${arch}" == "linux/amd64" ]]; then
        amd64="${digest}"
      else
        err="single-platform manifest is ${arch}, not linux/amd64"
      fi
    elif [[ "${amd64}" == "-" ]]; then
      err="multi-arch index has no linux/amd64 entry"
    fi
  else
    # Keep only skopeo's message (drop the `time="..." level=fatal` prefix so
    # the recorded error is deterministic) and unescape its inner quotes.
    err="$(sed -n 's/.*msg="\(.*\)"[[:space:]]*$/\1/p' "${WORK}/err.txt" | head -n1 | sed 's/\\"/"/g')"
    [[ -n "${err}" ]] || err="$(tr '\n' ' ' < "${WORK}/err.txt" | sed 's/[[:space:]]*$//')"
    err="${err:-skopeo inspect failed}"
  fi
  if [[ "${digest}" != "-" && -z "${err}" ]]; then
    ok=$((ok + 1)); echo "${digest:7:12} (amd64 ${amd64:7:12})"
  else
    failed=$((failed + 1)); echo "FAILED: ${err}"
  fi
  printf '%s\t%s\t%s\t%s\n' "${image}" "${digest}" "${amd64}" "${err}" >> "${WORK}/resolved.tsv"
done < "${WORK}/images.txt"
echo "resolved ${ok}/${n_images} images, ${failed} failed"

# --- 4. assemble the JSON document (sorted, deterministic) --------------------
RESOLVED_DATE="$(date -u +%Y-%m-%d)"
"${PY}" - "${WORK}/refs.tsv" "${WORK}/resolved.tsv" "${UPSTREAM_REPO}" "${REV}" "${UPSTREAM_FILE}" "${RESOLVED_DATE}" > "${WORK}/out.json" <<'PY'
import json, sys
refs, resolved, repo, rev, upfile, date = sys.argv[1:7]
used = {}
for line in open(refs, encoding="utf-8"):
    key, image = line.rstrip("\n").split("\t")
    used.setdefault(image, set()).add(key)
images = {}
for line in open(resolved, encoding="utf-8"):
    image, digest, amd64, err = line.rstrip("\n").split("\t")
    entry = {
        "digest": None if digest == "-" else digest,
        "amd64_digest": None if amd64 == "-" else amd64,
        "used_by": ", ".join(sorted(used.get(image, ()))),
    }
    if err:
        entry["error"] = err
    images[image] = entry
doc = {
    "source": {"repo": repo, "rev": rev, "file": upfile},
    "resolved": date,
    "images": dict(sorted(images.items())),
}
json.dump(doc, sys.stdout, indent=2, sort_keys=False)
sys.stdout.write("\n")
PY

# --- 5. write, or compare against the committed file --------------------------
if [[ "${CHECK}" -eq 0 ]]; then
  mkdir -p "$(dirname "${OUT_FILE}")"
  cp "${WORK}/out.json" "${OUT_FILE}"
  echo "wrote ${OUT_FILE}"
  [[ "${failed}" -eq 0 ]] || { echo "WARNING: ${failed} image(s) have digest null; see their \"error\" fields" >&2; exit 1; }
  exit 0
fi

[[ -f "${OUT_FILE}" ]] || { echo "--check: ${OUT_FILE} does not exist; run without --check first" >&2; exit 1; }
if "${PY}" - "${OUT_FILE}" "${WORK}/out.json" <<'PY'
import json, sys
old = json.load(open(sys.argv[1], encoding="utf-8"))
new = json.load(open(sys.argv[2], encoding="utf-8"))
problems, warnings = [], []
if old.get("source") != new["source"]:
    problems.append(f"source differs: committed {old.get('source')} vs upstream {new['source']}")
oi, ni = old.get("images", {}), new["images"]
for image in sorted(set(oi) | set(ni)):
    if image not in oi:
        problems.append(f"MISSING in committed file: {image}")
    elif image not in ni:
        problems.append(f"STALE (no longer upstream): {image}")
    else:
        o, n = oi[image], ni[image]
        if n.get("digest") is None and o.get("digest") is None:
            warnings.append(f"still unresolvable (as committed): {image} ({n.get('error', 'no error text')})")
        elif n.get("digest") is None:
            problems.append(f"UNRESOLVED now: {image} ({n.get('error', 'no error text')})")
        elif o.get("digest") is None:
            problems.append(f"NOW RESOLVABLE (committed null): {image} -> {n['digest']}; refresh the file")
        else:
            for field in ("digest", "amd64_digest"):
                if o.get(field) != n.get(field):
                    problems.append(f"CHANGED {field}: {image}: committed {o.get(field)} vs registry {n.get(field)} -- tag re-pointed upstream?")
for w in warnings:
    print("  WARN " + w)
if problems:
    print("--check FAILED:")
    for p in problems:
        print("  " + p)
    sys.exit(1)
print(f"--check OK: {len(ni)} images match the committed digests")
PY
then
  exit 0
else
  exit 1
fi
