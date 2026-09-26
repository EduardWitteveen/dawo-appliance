#!/usr/bin/env bash
#
# Cut a release of dawo-appliance (docs/releasing.md). Two re-entrant phases:
#
#   bash scripts/release.sh prepare 0.1.0
#       Branch release/v0.1.0 from origin/main, set manifest appliance.version
#       to 0.1.0, regenerate the checksum, commit, push, open a pull request.
#       Merge it through the normal GitHub workflow (AGENTS.md).
#
#   bash scripts/release.sh publish 0.1.0
#       On an up-to-date main whose manifest says 0.1.0: tag v0.1.0, build the
#       ISO from that exact commit, and create a DRAFT GitHub release with the
#       ISO, the manifest and their SHA-256 files. The draft is not public; the
#       maintainer reviews and publishes it on GitHub.
#
# Needs git, gh (logged in), python3, and for `publish` Nix + a clean tree.
# The version must be plain SemVer (no "v", no "-dev").
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

die() { echo "[release] ERROR: $*" >&2; exit 1; }
log() { echo "[release] $*"; }

phase="${1:-}"; version="${2:-}"
[[ "${phase}" == "prepare" || "${phase}" == "publish" ]] || die "usage: $0 prepare|publish X.Y.Z"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z (got '${version}')"
tag="v${version}"
manifest="manifest/appliance-manifest.json"

manifest_version() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["appliance"]["version"])' "${manifest}"
}

if [[ "${phase}" == "prepare" ]]; then
  [[ -z "$(git status --porcelain)" ]] || die "working tree not clean"
  git fetch -q origin
  git switch -q -c "release/${tag}" origin/main
  python3 - "${manifest}" "${version}" <<'PY'
import json, sys
p, v = sys.argv[1], sys.argv[2]
m = json.load(open(p, encoding="utf-8"))
m["appliance"]["version"] = v
open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
PY
  ( cd manifest && sha256sum appliance-manifest.json > appliance-manifest.json.sha256 )
  bash tests/test-bootstrap-dryrun.sh >/dev/null || die "dry-run suite fails with the new version"
  git add "${manifest}" "${manifest}.sha256"
  git commit -q -m "chore(release): ${tag}"
  git push -q -u origin "release/${tag}"
  gh pr create --title "chore(release): ${tag}" --body "Sets the manifest version to ${version} (the ISO built from the merge commit downloads and verifies the ${tag} release asset). After merge: \`bash scripts/release.sh publish ${version}\` (docs/releasing.md)." </dev/null
  log "prepared ${tag}; merge the PR, then run: bash scripts/release.sh publish ${version}"
  exit 0
fi

# --- publish -------------------------------------------------------------------
[[ -z "$(git status --porcelain)" ]] || die "working tree not clean"
git fetch -q origin --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "HEAD is not origin/main; git switch main && git pull --ff-only"
[[ "$(manifest_version)" == "${version}" ]] || die "manifest version is $(manifest_version), not ${version}; run prepare first"
command -v nix >/dev/null || die "nix is required to build the ISO"

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  [[ "$(git rev-list -n1 "${tag}")" == "$(git rev-parse HEAD)" ]] || die "tag ${tag} exists on another commit"
  log "tag ${tag} already exists on HEAD (re-entrant run)"
else
  git tag -a "${tag}" -m "dawo-appliance ${tag}"
  git push -q origin "${tag}"
fi

out="$(mktemp -d)"
log "building the ISO from ${tag} ..."
iso_dir="$(nix build .#installer-iso --no-link --print-out-paths --no-warn-dirty)/iso"
iso="$(find "${iso_dir}" -name '*.iso' | head -1)"
cp "${iso}" "${out}/dawo-appliance-installer-${tag}.iso"
cp "${manifest}" "${manifest}.sha256" "${out}/"
( cd "${out}" && sha256sum "dawo-appliance-installer-${tag}.iso" > "dawo-appliance-installer-${tag}.iso.sha256" )

if gh release view "${tag}" >/dev/null 2>&1 </dev/null; then
  log "release ${tag} exists; uploading assets again (--clobber)"
  gh release upload "${tag}" "${out}"/* --clobber </dev/null
else
  gh release create "${tag}" --draft --verify-tag --title "dawo-appliance ${tag} (experimental, unofficial)" \
    --notes "Experimental, unofficial demo appliance; not an official DAWO / Mijn Bureau / BZK distribution. Not for production (see README). Verification: docs/verification-latest.md at ${tag}. Assets: installer ISO, its SHA-256, the release manifest and its SHA-256." \
    "${out}"/* </dev/null
fi
rm -rf "${out}"
log "draft release ${tag} created; review and publish it on GitHub"
