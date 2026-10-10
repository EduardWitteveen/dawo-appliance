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
#       installer ISO and the live disk image from that exact commit, and
#       create a DRAFT GitHub release with the installer ISO, the manifest,
#       their SHA-256 files and the live image's SHA-256. The draft is not
#       public; the maintainer reviews and publishes it on GitHub.
#
#       The live image (~7 GB) is over GitHub's 2 GiB asset limit, so it goes
#       to SourceForge (maintainer decision, #192): with SF_USER set (an SSH
#       key on that SourceForge account) it is uploaded with rsync to
#       https://sourceforge.net/projects/dawo-appliance/files/v0.1.0/; without
#       it, the image stays in RELEASE_OUT (default ~/dawo-release/v0.1.0) and
#       the rsync command is printed.
#
# Needs git, gh (logged in), python3, and for `publish` Nix + a clean tree
# (and rsync + ssh for the SourceForge upload).
# The version must be SemVer X.Y.Z, or a release candidate X.Y.Z-rc.N
# (no "v", no "-dev"); a release candidate becomes a GitHub pre-release.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

die() { echo "[release] ERROR: $*" >&2; exit 1; }
log() { echo "[release] $*"; }

phase="${1:-}"; version="${2:-}"
[[ "${phase}" == "prepare" || "${phase}" == "publish" ]] || die "usage: $0 prepare|publish X.Y.Z"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || die "version must be X.Y.Z or X.Y.Z-rc.N (got '${version}')"
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
log "building the installer ISO from ${tag} ..."
iso_dir="$(nix build .#installer-iso --no-link --print-out-paths --no-warn-dirty)/iso"
iso="$(find "${iso_dir}" -name '*.iso' | head -1)"
cp "${iso}" "${out}/dawo-appliance-installer-${tag}.iso"
cp "${manifest}" "${manifest}.sha256" "${out}/"
( cd "${out}" && sha256sum "dawo-appliance-installer-${tag}.iso" > "dawo-appliance-installer-${tag}.iso.sha256" )

# The live disk image (Rufus/Etcher, #192), kept outside the temporary
# directory: it is too large to build or copy twice.
img_name="dawo-appliance-live-${tag}.img"
sf_dir="https://sourceforge.net/projects/dawo-appliance/files/${tag}/"
img_out="${RELEASE_OUT:-${HOME}/dawo-release/${tag}}"
mkdir -p "${img_out}"
log "building the live disk image from ${tag} ..."
img_dir="$(nix build .#appliance-live-img --no-link --print-out-paths --no-warn-dirty)/iso"
cp "${img_dir}/dawo-appliance-live.img" "${img_out}/${img_name}"
chmod u+w "${img_out}/${img_name}"
( cd "${img_out}" && sha256sum "${img_name}" > "${img_name}.sha256" )
cp "${img_out}/${img_name}.sha256" "${out}/"
img_sha="$(cut -d' ' -f1 "${img_out}/${img_name}.sha256")"
rsync_cmd=(rsync -av --progress -e ssh "${img_out}/${img_name}" "${img_out}/${img_name}.sha256"
  "${SF_USER:-<sourceforge-user>}@frs.sourceforge.net:/home/frs/project/dawo-appliance/${tag}/")
if [[ -n "${SF_USER:-}" ]]; then
  log "uploading ${img_name} to SourceForge as ${SF_USER} ..."
  "${rsync_cmd[@]}"
else
  log "SF_USER not set: upload the live image yourself (or in the Files tab of the SourceForge project):"
  log "  ${rsync_cmd[*]}"
fi
notes="Experimental, unofficial demo appliance; not an official DAWO / Mijn Bureau / BZK distribution. Not for production (see README). Verification: docs/verification-latest.md at ${tag}.

**Live USB (recommended):** download ${img_name} from SourceForge, ${sf_dir} (too large for GitHub), and write it with Rufus or balenaEtcher to a USB SSD of 64 GB or more (docs/live-usb.md, section 2a). SHA-256: ${img_sha} (also an asset here).

Assets here: the live image's SHA-256, the installer ISO and its SHA-256, the release manifest and its SHA-256."

if gh release view "${tag}" >/dev/null 2>&1 </dev/null; then
  log "release ${tag} exists; uploading assets again (--clobber)"
  gh release upload "${tag}" "${out}"/* --clobber </dev/null
else
  pre=(); [[ "${version}" == *-rc.* ]] && pre=(--prerelease)
  gh release create "${tag}" --draft --verify-tag "${pre[@]}" --title "dawo-appliance ${tag} (experimental, unofficial)" \
    --notes "${notes}" \
    "${out}"/* </dev/null
fi
rm -rf "${out}"
log "draft release ${tag} created; check that ${sf_dir} has ${img_name}, then review and publish the draft on GitHub"
