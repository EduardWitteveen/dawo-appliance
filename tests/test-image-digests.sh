#!/usr/bin/env bash
#
# Local test for the pinned container image digests (OQ-5).
# Requires no Nix, no root, and no network; only bash and Python 3
# (`python3`, or `python` as Windows Git Bash ships it).
# Runs on Windows Git Bash and in WSL/Linux.
#
# Asserts:
#   1. manifest/image-digests.json is well-formed JSON with the expected shape
#      (source.repo/rev/file, resolved date, images object).
#   2. Its source.rev equals mijn_bureau.rev in manifest/appliance-manifest.json
#      (digests were resolved for the revision we deploy).
#   3. Every image in the appliance manifest's mijn_bureau.charts.images_by_tag
#      has an entry in image-digests.json.
#   4. Every digest and amd64_digest matches ^sha256:[0-9a-f]{64}$. The one
#      tolerated exception is an entry the resolver marked unresolvable
#      ("digest": null plus a non-empty "error"), and only for an image that is
#      NOT in images_by_tag; such entries are reported as WARN.
#   5. The images object is sorted by key (deterministic output).
#
# Refresh the file with: bash scripts/resolve-image-digests.sh (needs network).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIGESTS="${REPO_ROOT}/manifest/image-digests.json"
MANIFEST="${REPO_ROOT}/manifest/appliance-manifest.json"

echo "test-image-digests: starting"
# Windows Git Bash usually ships `python` (3.x) without a `python3` alias.
PY="$(command -v python3 || command -v python || true)"
if [[ -z "${PY}" ]] || ! "${PY}" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)'; then
  echo "python 3 not found (looked for python3, python)"; exit 2
fi
[[ -f "${DIGESTS}" ]]  || { echo "digest file not found: ${DIGESTS} (run: bash scripts/resolve-image-digests.sh)"; exit 2; }
[[ -f "${MANIFEST}" ]] || { echo "manifest not found: ${MANIFEST}"; exit 2; }

if "${PY}" - "${DIGESTS}" "${MANIFEST}" <<'PY'
import json, re, sys

digests_path, manifest_path = sys.argv[1:3]
passed = failed = 0

def ok(msg):
    global passed
    print(f"  \033[32mPASS\033[0m {msg}"); passed += 1

def bad(msg):
    global failed
    print(f"  \033[31mFAIL\033[0m {msg}"); failed += 1

# --- 1. well-formed JSON with the expected shape ----------------------------
try:
    doc = json.load(open(digests_path, encoding="utf-8"))
except (ValueError, OSError) as e:
    print(f"  \033[31mFAIL\033[0m image-digests.json is not valid JSON: {e}")
    sys.exit(1)
shape_ok = (
    isinstance(doc, dict)
    and isinstance(doc.get("source"), dict)
    and all(isinstance(doc["source"].get(k), str) and doc["source"][k] for k in ("repo", "rev", "file"))
    and isinstance(doc.get("resolved"), str)
    and re.fullmatch(r"\d{4}-\d{2}-\d{2}", doc["resolved"]) is not None
    and isinstance(doc.get("images"), dict)
    and len(doc["images"]) > 0
)
if shape_ok:
    ok(f"image-digests.json is well-formed ({len(doc['images'])} images, resolved {doc['resolved']})")
else:
    bad("image-digests.json lacks source{repo,rev,file}, resolved (YYYY-MM-DD) or a non-empty images object")
    print(f"\ntest-image-digests: {passed} passed, {failed} failed")
    sys.exit(1)
images = doc["images"]

# --- 2. resolved for the mijn-bureau-infra revision we deploy ---------------
manifest = json.load(open(manifest_path, encoding="utf-8"))
mb_rev = manifest["mijn_bureau"]["rev"]
if doc["source"]["rev"] == mb_rev:
    ok(f"source.rev matches manifest mijn_bureau.rev ({mb_rev[:12]})")
else:
    bad(f"source.rev {doc['source']['rev'][:12]} != manifest mijn_bureau.rev {mb_rev[:12]} (re-run the resolver)")

# --- 3. every manifest images_by_tag image has an entry ---------------------
by_tag = manifest["mijn_bureau"]["charts"]["images_by_tag"]
missing = sorted(img for img in by_tag.values() if img not in images)
if not missing:
    ok(f"all {len(by_tag)} images_by_tag entries from the appliance manifest have a digest entry")
else:
    bad(f"{len(missing)} images_by_tag entries without a digest entry:")
    for m in missing:
        print(f"      | {m}")

# --- 4. digests are sha256 hex ----------------------------------------------
sha = re.compile(r"^sha256:[0-9a-f]{64}$")
bad_digests, unresolved = [], []
required = set(by_tag.values())
for image, entry in images.items():
    if not isinstance(entry, dict):
        bad_digests.append((image, "entry is not an object")); continue
    err = entry.get("error")
    if entry.get("digest") is None and entry.get("amd64_digest") is None \
            and isinstance(err, str) and err and image not in required:
        unresolved.append((image, err)); continue
    for field in ("digest", "amd64_digest"):
        v = entry.get(field)
        if not isinstance(v, str) or not sha.match(v):
            bad_digests.append((image, f"{field}={v!r}" + (f" error={err!r}" if err else "")))
for image, err in unresolved:
    print(f"  \033[33mWARN\033[0m unresolvable upstream image (not in images_by_tag): {image}")
    print(f"      | {err}")
if not bad_digests:
    ok(f"every digest and amd64_digest matches ^sha256:[0-9a-f]{{64}}$ "
       f"({len(images) - len(unresolved)} resolved, {len(unresolved)} recorded as unresolvable)")
else:
    bad(f"{len(bad_digests)} invalid or null digest field(s):")
    for image, why in bad_digests:
        print(f"      | {image}: {why}")

# --- 5. sorted, deterministic ----------------------------------------------
if list(images) == sorted(images):
    ok("images are sorted by reference")
else:
    bad("images are not sorted by reference (resolver output must be deterministic)")

print(f"\ntest-image-digests: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PY
then
  exit 0
else
  exit 1
fi
