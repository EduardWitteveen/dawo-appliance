#!/usr/bin/env bash
#
# Offline test for scripts/release.sh (#175). Needs no Nix, no network, no
# GitHub and no SourceForge: the script runs in a throw-away git repository
# whose `origin` is a local bare repository, with fake `nix`, `gh` and `rsync`
# on PATH that only record their arguments. Runs on Linux, WSL and Windows Git
# Bash (bash 4+, git, sha256sum, Python 3 as `python3` or `python`).
#
# Asserts:
#   1. `plan` (and no arguments) is a dry run: exit 0, NOT READY on a -dev
#      version, and it calls no nix/gh/rsync, makes no tag and writes no files.
#   2. Steps refuse a -dev version (no build), and an action mixed with step
#      options is refused.
#   3. `notes --version` previews the notes from CHANGELOG [Unreleased]: the
#      SourceForge link, the checksum instructions, Rufus/Etcher, links
#      rewritten to the tag on GitHub.
#   4. `prepare` sets the manifest version and checksum, turns [Unreleased]
#      into [X.Y.Z] - date, pushes the release branch and opens a PR.
#   5. After the merge `plan` is READY; `--build` calls `nix build
#      .#appliance-live-img`; `--stage` writes a verifiable SHA256SUMS and the
#      notes, and refuses an image that does not match its .sha256.
#   6. `--sourceforge-command` prints the rsync command and runs nothing;
#      `--sourceforge-upload` refuses without SF_USER.
#   7. `--github` tags the built commit, pushes the tag and creates a DRAFT
#      pre-release; it never publishes, and refuses a release that is
#      already published.
#   8. shellcheck on the script and this test (skipped when not installed).
# The bash -c snippets below get their values as "$1" on purpose.
# shellcheck disable=SC2016
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok() { echo "  PASS $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL $*"; fail=$((fail + 1)); }
check() { local d="$1"; shift; if "$@"; then ok "${d}"; else bad "${d}"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# --- fixture repo -----------------------------------------------------------------
git init -q --bare "${tmp}/origin.git"
repo="${tmp}/repo"
mkdir -p "${repo}/scripts" "${repo}/manifest"
cp "${REPO_ROOT}/scripts/release.sh" "${repo}/scripts/"
cp "${REPO_ROOT}/manifest/appliance-manifest.json" "${repo}/manifest/"
sed -i 's/"version": "[0-9.]*-dev"/"version": "0.1.0-dev"/' "${repo}/manifest/appliance-manifest.json"
(cd "${repo}/manifest" && sha256sum --text appliance-manifest.json > appliance-manifest.json.sha256)
cat > "${repo}/CHANGELOG.md" <<'EOF'
# Changelog

Intro with a [link](./docs/releasing.md).

## [Unreleased] — towards 0.1.0-rc.1

### Added
- Live disk image, see [live USB](./docs/live-usb.md).

## [0.0.1] - 2026-01-01

### Added
- Something old.
EOF
g() { git -C "${repo}" "$@"; }
g init -q -b main
g config user.email test@example.invalid
g config user.name test
g config commit.gpgsign false
g config tag.gpgsign false
g config core.autocrlf false
g add -A
g commit -q -m init
g remote add origin "${tmp}/origin.git"
g push -q -u origin main 2>/dev/null

# --- fakes ------------------------------------------------------------------------
bin="${tmp}/bin"; calls="${tmp}/calls"; mkdir -p "${bin}"; : > "${calls}"
cat > "${bin}/nix" <<EOF
#!/usr/bin/env bash
echo "nix \$*" >> "${calls}"
link=""; while ((\$#)); do [[ "\$1" == -o ]] && link="\$2"; shift; done
mkdir -p "\${link}/iso"
printf 'fake live image\n' > "\${link}/iso/dawo-appliance-live.img"
(cd "\${link}/iso" && sha256sum --text dawo-appliance-live.img > dawo-appliance-live.img.sha256)
EOF
cat > "${bin}/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "${calls}"
if [[ "\$1 \$2" == "release view" ]]; then
  [[ -f "${tmp}/gh-release-published" ]] || exit 1
  [[ "\$*" == *isDraft* ]] && echo false
fi
exit 0
EOF
cat > "${bin}/rsync" <<EOF
#!/usr/bin/env bash
echo "rsync \$*" >> "${calls}"
EOF
chmod +x "${bin}/nix" "${bin}/gh" "${bin}/rsync"

out="${tmp}/out"
rel() { (cd "${repo}" && PATH="${bin}:${PATH}" RELEASE_OUT="${out}" RELEASE_SKIP_SUITE=1 bash scripts/release.sh "$@"); }

echo "test-release: scripts/release.sh in a throw-away repository"

# --- 1. plan is a dry run ---------------------------------------------------------
plan_out="$(rel plan 2>&1)" && rc=0 || rc=$?
check "plan exits 0" test "${rc}" = 0
check "plan names the version and tag" grep -q "tag         v0.1.0-dev" <<<"${plan_out}"
check "plan is NOT READY on a -dev version" grep -q "NOT READY" <<<"${plan_out}"
check "plan says how to get ready (prepare)" grep -q "release.sh prepare" <<<"${plan_out}"
check "plan shows the live image build" grep -q "appliance-live-img" <<<"${plan_out}"
check "plan shows the SourceForge rsync target" grep -q "frs.sourceforge.net:/home/frs/project/dawo-appliance/v0.1.0-dev/" <<<"${plan_out}"
check "plan says the GitHub release is a draft" grep -q -- "--draft" <<<"${plan_out}"
check "plan mentions no installer ISO" bash -c '! grep -qi "installer" <<<"$1"' _ "${plan_out}"
noarg_out="$(rel 2>&1)"
check "no arguments is plan" test "${noarg_out}" = "${plan_out}"
check "plan called no nix, gh or rsync" test ! -s "${calls}"
check "plan made no tag" test -z "$(g tag -l)"
check "plan wrote no files" test ! -e "${out}"
check "plan left the tree clean" test -z "$(g status --porcelain)"

# --- 2. refusals -------------------------------------------------------------------
if rel --build >/dev/null 2>&1; then bad "--build on a -dev version refused"; else ok "--build on a -dev version refused"; fi
check "the refused build called no nix" test ! -s "${calls}"
if rel plan --build >/dev/null 2>&1; then bad "plan with a step option refused"; else ok "plan with a step option refused"; fi
if rel --build --version 0.1.0-rc.1 >/dev/null 2>&1; then bad "--version with a step refused"; else ok "--version with a step refused"; fi
if rel bogus >/dev/null 2>&1; then bad "unknown argument refused"; else ok "unknown argument refused"; fi
check "--help prints the usage" bash -c 'grep -q -- "--sourceforge-command" <<<"$1"' _ "$(rel --help)"

# --- 3. notes preview ---------------------------------------------------------------
notes="$(rel notes --version 0.1.0-rc.1)"
check "notes: title with tag" grep -q "^# dawo-appliance v0.1.0-rc.1 (experimental, unofficial)" <<<"${notes}"
check "notes: SourceForge download link" grep -qF "https://sourceforge.net/projects/dawo-appliance/files/v0.1.0-rc.1/dawo-appliance-live.img/download" <<<"${notes}"
check "notes: Windows checksum (Get-FileHash)" grep -q "Get-FileHash" <<<"${notes}"
check "notes: Rufus and balenaEtcher" grep -q "Rufus.*balenaEtcher" <<<"${notes}"
check "notes: release candidate sentence" grep -q "release candidate" <<<"${notes}"
check "notes: the [Unreleased] changes" grep -q "Live disk image, see" <<<"${notes}"
check "notes: not the older section" bash -c '! grep -q "Something old" <<<"$1"' _ "${notes}"
check "notes: relative links point at the tag" grep -qF "](https://github.com/EduardWitteveen/dawo-appliance/blob/v0.1.0-rc.1/docs/live-usb.md)" <<<"${notes}"
check "notes: says it is not official" grep -q "Not an official DAWO" <<<"${notes}"

# --- 4. prepare ---------------------------------------------------------------------
if rel prepare 0.1.0-rc.1 >/dev/null 2>&1; then ok "prepare 0.1.0-rc.1 runs"; else bad "prepare 0.1.0-rc.1 runs"; fi
check "prepare: manifest version" grep -q '"version": "0.1.0-rc.1"' "${repo}/manifest/appliance-manifest.json"
check "prepare: manifest checksum valid" bash -c 'cd "$1/manifest" && sha256sum -c --quiet appliance-manifest.json.sha256' _ "${repo}"
check "prepare: CHANGELOG section dated" grep -q "^## \[0.1.0-rc.1\] - [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$" "${repo}/CHANGELOG.md"
check "prepare: a fresh [Unreleased] above it" bash -c 'grep "^## " "$1" | head -2 | tr "\n" "|" | grep -q "^## \[Unreleased\]|## \[0.1.0-rc.1\]"' _ "${repo}/CHANGELOG.md"
check "prepare: release branch pushed" git -C "${tmp}/origin.git" show-ref --verify --quiet refs/heads/release/v0.1.0-rc.1
check "prepare: PR opened" grep -q "^gh pr create" "${calls}"
check "prepare: no tag yet" test -z "$(g tag -l)"
# The PR is merged (fast-forward stands in for the rebase merge).
g switch -q main
g merge -q --ff-only release/v0.1.0-rc.1
g push -q origin main 2>/dev/null
g fetch -q origin
: > "${calls}"

# --- 5. plan READY, build, stage -----------------------------------------------------
plan_out="$(rel plan)"
check "plan READY after the merge" grep -q "READY: --build and --github would run" <<<"${plan_out}"
check "plan: pre-release for an rc" grep -q -- "--prerelease" <<<"${plan_out}"
check "plan: changelog section found" grep -q "section \[0.1.0-rc.1\]" <<<"${plan_out}"
notes="$(rel notes)"
check "notes after prepare use the [0.1.0-rc.1] section" grep -q "Live disk image, see" <<<"${notes}"

echo dirty >> "${repo}/CHANGELOG.md"
if rel --build >/dev/null 2>&1; then bad "--build refuses a dirty tree"; else ok "--build refuses a dirty tree"; fi
g checkout -q -- CHANGELOG.md
g commit -q --allow-empty -m "local only"
if rel --build >/dev/null 2>&1; then bad "--build refuses a HEAD that is not origin/main"; else ok "--build refuses a HEAD that is not origin/main"; fi
g reset -q --hard origin/main
check "the refused builds called no nix" test ! -s "${calls}"

if rel --build >/dev/null 2>&1; then ok "--build runs"; else bad "--build runs"; fi
check "--build: nix build .#appliance-live-img" grep -q "^nix build .#appliance-live-img -o ${out}/v0.1.0-rc.1/result-live-img" "${calls}"
check "--build: records the commit" test "$(cat "${out}/v0.1.0-rc.1/commit" 2>/dev/null)" = "$(g rev-parse HEAD)"

stage="${tmp}/stage"
if rel --stage "${stage}" >/dev/null 2>&1; then ok "--stage runs"; else bad "--stage runs"; fi
for f in dawo-appliance-live.img dawo-appliance-live.img.sha256 SHA256SUMS appliance-manifest.json appliance-manifest.json.sha256 RELEASE-NOTES.md; do
  check "--stage: ${f}" test -s "${stage}/${f}"
done
check "--stage: SHA256SUMS verifies" bash -c 'cd "$1" && sha256sum -c --quiet SHA256SUMS' _ "${stage}"
check "--stage: SHA256SUMS lists the image and the manifest" test "$(cut -d' ' -f3 "${stage}/SHA256SUMS" | tr '\n' ' ')" = "dawo-appliance-live.img appliance-manifest.json "
img_sha="$(cut -d' ' -f1 "${stage}/dawo-appliance-live.img.sha256")"
check "--stage: notes carry the image SHA-256" grep -q "${img_sha}" "${stage}/RELEASE-NOTES.md"
check "--stage: notes carry the commit" grep -q "$(g rev-parse --short=12 HEAD)" "${stage}/RELEASE-NOTES.md"
check "--stage: no installer ISO staged" test -z "$(find "${stage}" -name '*.iso')"
mkdir -p "${tmp}/badimg"
printf 'one\n' > "${tmp}/badimg/x.img"
printf '%064d  dawo-appliance-live.img\n' 0 > "${tmp}/badimg/x.img.sha256"
if rel --stage "${tmp}/stage-bad" --image "${tmp}/badimg/x.img" >/dev/null 2>&1; then bad "--stage refuses a mismatching .sha256"; else ok "--stage refuses a mismatching .sha256"; fi

# --- 6. SourceForge -------------------------------------------------------------------
sf_out="$(rel --stage "${stage}" --sourceforge-command 2>&1 || true)"
check "--sourceforge-command prints rsync to frs" grep -q "rsync -av --progress -e ssh ${stage}/dawo-appliance-live.img .*<sourceforge-user>@frs.sourceforge.net:/home/frs/project/dawo-appliance/v0.1.0-rc.1/" <<<"${sf_out}"
check "--sourceforge-command runs no rsync" bash -c '! grep -q "^rsync" "$1"' _ "${calls}"
if (unset SF_USER; rel --stage "${stage}" --sourceforge-upload >/dev/null 2>&1); then bad "--sourceforge-upload refuses without SF_USER"; else ok "--sourceforge-upload refuses without SF_USER"; fi
check "the refused upload ran no rsync" bash -c '! grep -q "^rsync" "$1"' _ "${calls}"

# --- 7. GitHub draft -------------------------------------------------------------------
: > "${calls}"
if rel --stage "${stage}" --github >/dev/null 2>&1; then ok "--github runs"; else bad "--github runs"; fi
check "--github: tag on the built commit" test "$(g rev-list -n1 v0.1.0-rc.1 2>/dev/null)" = "$(g rev-parse HEAD)"
check "--github: tag pushed" git -C "${tmp}/origin.git" show-ref --verify --quiet refs/tags/v0.1.0-rc.1
create="$(grep "^gh release create" "${calls}" || true)"
check "--github: draft" grep -q -- "--draft" <<<"${create}"
check "--github: pre-release" grep -q -- "--prerelease" <<<"${create}"
check "--github: notes file" grep -q -- "--notes-file ${stage}/RELEASE-NOTES.md" <<<"${create}"
check "--github: SHA256SUMS asset" grep -q "${stage}/SHA256SUMS" <<<"${create}"
check "--github: no image asset (over 2 GiB)" bash -c '! grep -q "stage/dawo-appliance-live.img " <<<"$1 "' _ "${create}"
check "--github: never publishes" bash -c '! grep -q -- "--draft=false\|publish" "$1"' _ "${calls}"
touch "${tmp}/gh-release-published"
if rel --stage "${stage}" --github >/dev/null 2>&1; then bad "--github refuses a published release"; else ok "--github refuses a published release"; fi
check "the published release was not edited" bash -c '! grep -q "^gh release \(edit\|upload\)" "$1"' _ "${calls}"

# --- 8. shellcheck ---------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck" shellcheck "${REPO_ROOT}/scripts/release.sh" "${REPO_ROOT}/tests/test-release.sh"
else
  echo "  SKIP shellcheck (not installed)"
fi

echo "test-release: ${pass} passed, ${fail} failed"
((fail == 0))
