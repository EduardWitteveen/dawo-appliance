#!/usr/bin/env bash
#
# Cut a release of dawo-appliance (docs/releasing.md). Experimental and
# unofficial. The release artefact is the LIVE disk image (ADR 0006, #192):
# dawo-appliance-live.img for Rufus / balenaEtcher / dd, ~7 GB, hosted on
# SourceForge because GitHub release assets are limited to 2 GiB (maintainer
# decision, #192). The GitHub release carries the notes, SHA256SUMS, the
# image's .sha256, the release manifest and the SourceForge link.
#
# Version and tag come from appliance.version in manifest/appliance-manifest.json
# (tag = "v" + version). Steps, in this order when combined:
#
#   bash scripts/release.sh [plan]       (default) show the version, the checks
#                                        and what every step would do. Builds,
#                                        writes, uploads and pushes nothing.
#   bash scripts/release.sh prepare X.Y.Z
#                                        branch release/vX.Y.Z from origin/main,
#                                        set the manifest version, regenerate its
#                                        checksum, turn CHANGELOG [Unreleased]
#                                        into [X.Y.Z] - today, push, open a PR.
#   bash scripts/release.sh notes        print the release notes (from CHANGELOG.md)
#
#   bash scripts/release.sh --build      build .#appliance-live-img from HEAD
#                                        (clean tree, HEAD = origin/main, release
#                                        version); out-link and commit under
#                                        RELEASE_OUT/vX.Y.Z/
#                           --stage DIR  copy the image, its .sha256, the manifest
#                                        and its .sha256 to DIR, verify them, write
#                                        SHA256SUMS and RELEASE-NOTES.md
#                           --sourceforge-command
#                                        print the rsync command that uploads the
#                                        staged image to SourceForge (the
#                                        maintainer runs it with their own key)
#                           --sourceforge-upload
#                                        run that command; only with SF_USER set
#                                        and an ssh-agent holding the key
#                           --github     tag vX.Y.Z on the built commit, push the
#                                        tag, create a DRAFT GitHub release with
#                                        the notes and the small assets; a
#                                        release candidate is a pre-release.
#                                        Never publishes: the maintainer reviews
#                                        and publishes the draft on GitHub.
#
# Options: --stage DIR (default RELEASE_OUT/vX.Y.Z/stage), --image PATH (stage
# this image instead of the build's out-link), --version V (plan/notes only:
# preview another version than the manifest's).
# Environment: RELEASE_OUT (default ~/dawo-release), RELEASE_FLAKE (default ".";
# build from a real git checkout so the image carries its commit), SF_USER.
#
# This script never handles credentials: gh uses its own login, rsync/ssh the
# maintainer's agent. The installer ISO is no longer part of a release (ADR
# 0006 made the live USB the default; docs/releasing.md).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

die() { echo "[release] ERROR: $*" >&2; exit 1; }
log() { echo "[release] $*"; }

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; }

REPO_URL="https://github.com/EduardWitteveen/dawo-appliance"
SF_PROJECT="dawo-appliance"
IMG="dawo-appliance-live.img"
MANIFEST="manifest/appliance-manifest.json"
CHANGELOG="CHANGELOG.md"
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$'

py() {
  local p
  for p in python3 python; do
    if command -v "${p}" >/dev/null 2>&1 && "${p}" -c 'import sys; sys.exit(sys.version_info[0] != 3)' >/dev/null 2>&1; then
      "${p}" "$@"; return
    fi
  done
  die "python 3 is required (looked for python3, python)"
}

manifest_version() {
  py -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["appliance"]["version"])' "${MANIFEST}"
}

# --- arguments -------------------------------------------------------------------
action=""; prepare_version=""; version_override=""
do_build=0; do_stage=0; do_sf_cmd=0; do_sf_upload=0; do_github=0
stage_dir=""; image_src=""
while (($#)); do
  case "$1" in
    plan | notes) [[ -z "${action}" ]] || die "one action only"; action="$1"; shift ;;
    prepare) [[ -z "${action}" ]] || die "one action only"; action=prepare; prepare_version="${2:-}"; shift; (($#)) && shift ;;
    --build) do_build=1; shift ;;
    --stage) [[ -n "${2:-}" && "${2}" != --* ]] || die "--stage needs a directory"; do_stage=1; stage_dir="$2"; shift 2 ;;
    --image) [[ -n "${2:-}" ]] || die "--image needs a path"; image_src="$2"; shift 2 ;;
    --sourceforge-command) do_sf_cmd=1; shift ;;
    --sourceforge-upload) do_sf_upload=1; shift ;;
    --github) do_github=1; shift ;;
    --version) [[ -n "${2:-}" ]] || die "--version needs a value"; version_override="$2"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown argument '$1' (see --help)" ;;
  esac
done
steps=$((do_build + do_stage + do_sf_cmd + do_sf_upload + do_github))
if [[ -z "${action}" ]]; then
  ((steps > 0)) && action=steps || action=plan
elif ((steps > 0)); then
  die "'${action}' takes no step options; plan describes every step"
fi

if [[ "${action}" == "prepare" ]]; then
  version="${prepare_version}"
  [[ "${version}" =~ ${VERSION_RE} ]] || die "usage: $0 prepare X.Y.Z|X.Y.Z-rc.N (got '${version}')"
elif [[ -n "${version_override}" ]]; then
  [[ "${action}" == "plan" || "${action}" == "notes" ]] || die "--version is for plan/notes only; steps use the manifest version"
  version="${version_override}"
else
  version="$(manifest_version)"
fi
tag="v${version}"
out_root="${RELEASE_OUT:-${HOME}/dawo-release}"
work="${out_root}/${tag}"
[[ -n "${stage_dir}" ]] || stage_dir="${work}/stage"
[[ -n "${image_src}" ]] || image_src="${work}/result-live-img/iso/${IMG}"
flake="${RELEASE_FLAKE:-.}"
sf_dir_url="https://sourceforge.net/projects/${SF_PROJECT}/files/${tag}/"
sf_img_url="${sf_dir_url}${IMG}/download"
sf_target="${SF_USER:-<sourceforge-user>}@frs.sourceforge.net:/home/frs/project/${SF_PROJECT}/${tag}/"

# --- helpers ---------------------------------------------------------------------

# The CHANGELOG section for the version, else [Unreleased] (before prepare).
changelog_section() {
  local section
  section="$(awk -v h="## [$1]" '/^## / { if (on) exit; if (index($0, h) == 1) on = 1; next } on { print }' "${CHANGELOG}")"
  if [[ -z "${section//[[:space:]]/}" ]]; then
    section="$(awk '/^## / { if (on) exit; if (index($0, "## [Unreleased]") == 1) on = 1; next } on { print }' "${CHANGELOG}")"
  fi
  # Relative links point at the tagged tree on GitHub (a release body has no base).
  sed -e "s#](\./#](${REPO_URL}/blob/${tag}/#g" -e '/./,$!d' <<<"${section}"
}

# bullets PREFIX TEXT: every line of TEXT with PREFIX in front.
bullets() {
  local l
  while IFS= read -r l; do printf '%s%s\n' "$1" "${l}"; done <<<"$2"
}

changelog_has_section() { grep -q "^## \[$1\]" "${CHANGELOG}"; }

# release_notes SHA256 SIZE_BYTES COMMIT
release_notes() {
  local sha="$1" size="$2" commit="$3" gb pre=""
  if [[ "${size}" =~ ^[0-9]+$ ]]; then
    gb="$(awk -v b="${size}" 'BEGIN { printf "%.1f GB", b / 1e9 }')"
  else
    gb="about 7 GB"
  fi
  [[ "${version}" == *-rc.* ]] && pre=" This is a release candidate, for testing on real hardware."
  cat <<EOF
# dawo-appliance ${tag} (experimental, unofficial)

> Experimental, unofficial demo appliance. Not an official DAWO / Mijn Bureau / BZK distribution. Not for production or real data (see the README).${pre}

## Download

The live disk image is on SourceForge, because it is larger than GitHub's 2 GiB limit for release assets:

- **[${IMG}](${sf_img_url})** (${gb}), folder ${sf_dir_url}
- SHA-256: \`${sha}\` (also in \`SHA256SUMS\` and \`${IMG}.sha256\` below)

Check the download before writing it: on Windows \`(Get-FileHash .\\${IMG} -Algorithm SHA256).Hash\` must equal the SHA-256 above (case does not matter); on Linux \`sha256sum -c --ignore-missing SHA256SUMS\` in the download folder.

Write the image **as is** to a USB SSD of 64 GB or more with [Rufus](https://rufus.ie) or [balenaEtcher](https://etcher.balena.io) (or \`dd\`); this erases the USB disk. Boot the laptop from it; the first boot grows the data partition \`DAWO_LOGS\` to the end of the USB disk. Details: [docs/live-usb.md](${REPO_URL}/blob/${tag}/docs/live-usb.md).

Assets here: \`SHA256SUMS\`, \`${IMG}.sha256\`, and the release manifest \`appliance-manifest.json\` with its \`.sha256\` (every pinned version of this release). Built from commit \`${commit}\` (tag \`${tag}\`). Verification: [docs/verification-latest.md](${REPO_URL}/blob/${tag}/docs/verification-latest.md) at this tag.

## Changes

EOF
  changelog_section "${version}"
}

# Problems that stop --build and --github; printed by plan.
release_problems() {
  local p=()
  [[ "${version}" =~ ${VERSION_RE} ]] || p+=("version '${version}' is not a release (X.Y.Z or X.Y.Z-rc.N); run: bash scripts/release.sh prepare X.Y.Z-rc.N, merge the PR")
  if [[ -n "${version_override}" && "${version_override}" != "$(manifest_version)" ]]; then
    p+=("manifest version is $(manifest_version), not ${version_override}; run prepare ${version_override} first")
  fi
  [[ -z "$(git status --porcelain)" ]] || p+=("working tree not clean")
  local head_rev main
  head_rev="$(git rev-parse HEAD)"
  main="$(git rev-parse -q --verify refs/remotes/origin/main || true)"
  [[ "${head_rev}" == "${main}" ]] || p+=("HEAD is not origin/main; git switch main && git pull --ff-only")
  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    [[ "$(git rev-list -n1 "${tag}")" == "${head_rev}" ]] || p+=("tag ${tag} exists on another commit")
  fi
  ((${#p[@]} == 0)) || printf '%s\n' "${p[@]}"
}

require_release() {
  local problems
  problems="$(release_problems)"
  [[ -z "${problems}" ]] || die "not ready for ${tag}:
$(bullets "  - " "${problems}")"
}

sf_command() {
  printf 'rsync -av --progress -e ssh %s %s %s %s\n' \
    "${stage_dir}/${IMG}" "${stage_dir}/${IMG}.sha256" "${stage_dir}/SHA256SUMS" "${sf_target}"
}

# --- plan --------------------------------------------------------------------------
if [[ "${action}" == "plan" ]]; then
  echo "dawo-appliance release plan (dry run: nothing is built, written, uploaded or pushed)"
  echo
  echo "  version     ${version}   (manifest: $(manifest_version))"
  echo "  tag         ${tag}$([[ "${version}" == *-rc.* ]] && echo '   (release candidate: GitHub pre-release)')"
  echo "  commit      $(git rev-parse --short=12 HEAD)"
  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    echo "  tag state   exists on $(git rev-list -n1 "${tag}" | cut -c1-12)"
  else
    echo "  tag state   not yet created (made by --github on the built commit)"
  fi
  if changelog_has_section "${version}"; then
    echo "  changelog   section [${version}]"
  else
    echo "  changelog   no [${version}] section yet: the notes use [Unreleased] (prepare renames it)"
  fi
  echo
  problems="$(release_problems)"
  if [[ -z "${problems}" ]]; then
    echo "  checks      READY: --build and --github would run"
  else
    echo "  checks      NOT READY: --build and --github would refuse:"
    bullets "                - " "${problems}"
  fi
  echo
  echo "Steps (bash scripts/release.sh --build --stage DIR --sourceforge-command --github):"
  echo "  --build                nix build ${flake}#appliance-live-img -o ${work}/result-live-img"
  echo "  --stage DIR            DIR (default ${work}/stage) gets:"
  echo "                           ${IMG}, ${IMG}.sha256 (checked), SHA256SUMS,"
  echo "                           appliance-manifest.json + .sha256 (checked), RELEASE-NOTES.md"
  echo "  --sourceforge-command  prints, for the maintainer to run with their own SSH key:"
  echo "                           $(sf_command)"
  echo "                         (or upload in the SourceForge web UI: Files, Add Folder ${tag}, Add File)"
  echo "  --github               git tag -a ${tag} on the built commit, git push origin ${tag},"
  echo "                         gh release create ${tag} --draft$([[ "${version}" == *-rc.* ]] && echo ' --prerelease') --notes-file DIR/RELEASE-NOTES.md"
  echo "                           with SHA256SUMS, ${IMG}.sha256, appliance-manifest.json(.sha256)"
  echo "                         Never published automatically: review the draft on GitHub."
  echo
  echo "Download link in the notes: ${sf_img_url}"
  echo "Preview of the notes: bash scripts/release.sh notes$([[ -n "${version_override}" ]] && echo " --version ${version}")"
  exit 0
fi

# --- notes -------------------------------------------------------------------------
if [[ "${action}" == "notes" ]]; then
  sha="<sha256 of ${IMG}>"; size=""
  if [[ -f "${stage_dir}/${IMG}.sha256" ]]; then
    sha="$(cut -d' ' -f1 "${stage_dir}/${IMG}.sha256")"
    size="$(stat -c %s "${stage_dir}/${IMG}" 2>/dev/null || true)"
  fi
  release_notes "${sha}" "${size}" "$(git rev-parse --short=12 HEAD)"
  exit 0
fi

# --- prepare -----------------------------------------------------------------------
if [[ "${action}" == "prepare" ]]; then
  [[ -z "$(git status --porcelain)" ]] || die "working tree not clean"
  git fetch -q origin
  git switch -q -c "release/${tag}" origin/main
  py - "${MANIFEST}" "${version}" "${CHANGELOG}" "$(date +%Y-%m-%d)" <<'PY'
import json, re, sys
p, v, cl, today = sys.argv[1:5]
m = json.load(open(p, encoding="utf-8"))
m["appliance"]["version"] = v
open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
text = open(cl, encoding="utf-8").read()
if not re.search(r"^## \[" + re.escape(v) + r"\]", text, re.M):
    text, n = re.subn(r"^## \[Unreleased\].*$", "## [Unreleased]\n\n## [" + v + "] - " + today, text, count=1, flags=re.M)
    if n != 1:
        sys.exit("CHANGELOG.md has no '## [Unreleased]' section")
    open(cl, "w", encoding="utf-8", newline="\n").write(text)
PY
  (cd manifest && sha256sum --text appliance-manifest.json > appliance-manifest.json.sha256)
  if [[ "${RELEASE_SKIP_SUITE:-}" != 1 ]]; then # test hook (tests/test-release.sh)
    bash tests/test-bootstrap-dryrun.sh >/dev/null || die "dry-run suite fails with the new version"
  fi
  git add "${MANIFEST}" "${MANIFEST}.sha256" "${CHANGELOG}"
  git commit -q -m "chore(release): ${tag}"
  git push -q -u origin "release/${tag}"
  gh pr create --title "chore(release): ${tag}" --body "Sets the manifest version to ${version} and dates the CHANGELOG section. After merge, on an up-to-date main: \`bash scripts/release.sh plan\`, then \`bash scripts/release.sh --build --stage DIR --sourceforge-command\`, upload, \`--github\` (docs/releasing.md)." </dev/null
  log "prepared ${tag}; merge the PR, then: git switch main && git pull --ff-only && bash scripts/release.sh plan"
  exit 0
fi

# --- steps -------------------------------------------------------------------------
[[ "${version}" =~ ${VERSION_RE} ]] || die "manifest version '${version}' is not a release; run prepare first (see plan)"

if ((do_build)); then
  git fetch -q origin --tags
  require_release
  command -v nix >/dev/null || die "nix is required to build the image (run this in WSL/Linux)"
  mkdir -p "${work}"
  log "building the live disk image for ${tag} from $(git rev-parse --short=12 HEAD) (~7 GB, takes a while) ..."
  nix build "${flake}#appliance-live-img" -o "${work}/result-live-img" --no-warn-dirty -L
  git rev-parse HEAD > "${work}/commit"
  log "built: ${work}/result-live-img/iso/${IMG}"
fi

if ((do_stage)); then
  [[ -f "${image_src}" ]] || die "no image at ${image_src}; run --build first (or give --image PATH)"
  mkdir -p "${stage_dir}"
  log "staging ${tag} in ${stage_dir} ..."
  cp -f "${image_src}" "${stage_dir}/${IMG}"
  chmod u+w "${stage_dir}/${IMG}"
  if [[ -f "${image_src}.sha256" ]]; then
    cp -f "${image_src}.sha256" "${stage_dir}/${IMG}.sha256"
    (cd "${stage_dir}" && sha256sum -c --quiet "${IMG}.sha256") || die "the staged image does not match its .sha256"
  else
    (cd "${stage_dir}" && sha256sum --text "${IMG}" > "${IMG}.sha256")
  fi
  cp -f "${MANIFEST}" "${MANIFEST}.sha256" "${stage_dir}/"
  (cd "${stage_dir}" && sha256sum -c --quiet appliance-manifest.json.sha256) || die "the manifest does not match its .sha256"
  cat "${stage_dir}/${IMG}.sha256" "${stage_dir}/appliance-manifest.json.sha256" > "${stage_dir}/SHA256SUMS"
  commit="$(cat "${work}/commit" 2>/dev/null || git rev-parse HEAD)"
  release_notes "$(cut -d' ' -f1 "${stage_dir}/${IMG}.sha256")" "$(stat -c %s "${stage_dir}/${IMG}")" "${commit:0:12}" \
    > "${stage_dir}/RELEASE-NOTES.md"
  log "staged: $(cd "${stage_dir}" && echo *)"
fi

if ((do_sf_cmd || do_sf_upload)); then
  [[ -f "${stage_dir}/SHA256SUMS" ]] || die "nothing staged in ${stage_dir}; run --stage first"
fi
if ((do_sf_cmd)); then
  log "upload the image to SourceForge with your own SSH key (frs.sourceforge.net):"
  echo "  $(sf_command)"
  log "or in the web UI: ${sf_dir_url%"${tag}/"} > Files > Add Folder '${tag}' > Add File (the three files above)"
  log "check afterwards: ${sf_img_url}"
fi
if ((do_sf_upload)); then
  [[ -n "${SF_USER:-}" ]] || die "--sourceforge-upload needs SF_USER (your SourceForge user name)"
  [[ -n "${SSH_AUTH_SOCK:-}" ]] || die "--sourceforge-upload needs an ssh-agent with your SourceForge key (SSH_AUTH_SOCK is empty)"
  command -v rsync >/dev/null || die "rsync is required"
  log "uploading to ${sf_target} ..."
  rsync -av --progress -e ssh "${stage_dir}/${IMG}" "${stage_dir}/${IMG}.sha256" "${stage_dir}/SHA256SUMS" "${sf_target}"
fi

if ((do_github)); then
  for f in RELEASE-NOTES.md SHA256SUMS "${IMG}.sha256" appliance-manifest.json appliance-manifest.json.sha256; do
    [[ -f "${stage_dir}/${f}" ]] || die "missing ${stage_dir}/${f}; run --stage first"
  done
  command -v gh >/dev/null || die "gh (logged in) is required"
  git fetch -q origin --tags
  require_release
  head="$(git rev-parse HEAD)"
  if [[ -f "${work}/commit" && "$(cat "${work}/commit")" != "${head}" ]]; then
    die "the image was built from $(cut -c1-12 "${work}/commit"), HEAD is ${head:0:12}; build again"
  fi
  if ! git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    git tag -a "${tag}" -m "dawo-appliance ${tag} (experimental, unofficial)"
    log "tagged ${tag} on ${head:0:12}"
  fi
  git push -q origin "refs/tags/${tag}"
  assets=("${stage_dir}/SHA256SUMS" "${stage_dir}/${IMG}.sha256" "${stage_dir}/appliance-manifest.json" "${stage_dir}/appliance-manifest.json.sha256")
  if gh release view "${tag}" >/dev/null 2>&1 </dev/null; then
    [[ "$(gh release view "${tag}" --json isDraft -q .isDraft </dev/null)" == "true" ]] \
      || die "release ${tag} is already published; not touching it"
    log "draft ${tag} exists: updating its notes and assets"
    gh release edit "${tag}" --notes-file "${stage_dir}/RELEASE-NOTES.md" </dev/null
    gh release upload "${tag}" "${assets[@]}" --clobber </dev/null
  else
    pre=(); [[ "${version}" == *-rc.* ]] && pre=(--prerelease)
    gh release create "${tag}" --draft --verify-tag "${pre[@]}" \
      --title "dawo-appliance ${tag} (experimental, unofficial)" \
      --notes-file "${stage_dir}/RELEASE-NOTES.md" "${assets[@]}" </dev/null
  fi
  log "DRAFT release ${tag} is ready. Check that ${sf_img_url} downloads, then review and publish the draft on GitHub."
fi
