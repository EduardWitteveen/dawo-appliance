#!/usr/bin/env bash
#
# Refresh docs/screenshots/ from the automated boot tests.
#
# Why: the README should show what the appliance looks like, and those pictures
# must be trustworthy — taken from the pinned configuration by a reproducible
# test run, never hand-made or retouched. So the only source of screenshots is
# the NixOS VM tests (`test-installer-boot`, `test-appliance-boot`), which
# save PNGs into their result directories. This script builds the tests (a
# cached pass is fine; FORCE=1 re-runs them), copies the PNGs into
# docs/screenshots/ under stable names, and records provenance (date, git
# revision, pins) in docs/screenshots/PROVENANCE.md.
#
# When: on every slice completion and every upstream pin bump, before updating
# the README. Needs Linux + Nix + KVM (on this machine: WSL Ubuntu-24.04).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
out_dir="docs/screenshots"
mkdir -p "${out_dir}"

declare -a rebuild=()
[[ "${FORCE:-0}" -eq 1 ]] && rebuild=(--rebuild)

copy() {
  # copy TEST-ATTR SOURCE-NAME DEST-NAME
  local attr="$1" src="$2" dest="$3" result
  echo "==> ${attr} → ${out_dir}/${dest}"
  result="$(nix build "${rebuild[@]}" ".#${attr}" --no-link --print-out-paths --no-warn-dirty)"
  if [[ -f "${result}/${src}" ]]; then
    cp -f "${result}/${src}" "${out_dir}/${dest}"
    chmod 644 "${out_dir}/${dest}"
    echo "    ok ($(stat -c %s "${out_dir}/${dest}") bytes)"
  else
    echo "    MISSING: ${result}/${src}" >&2
    return 1
  fi
}

copy test-installer-boot installer-plan.png installer-plan.png
copy test-appliance-boot desktop.png appliance-desktop.png

rev="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
dirty=""
[[ -n "$(git status --porcelain 2>/dev/null)" ]] && dirty=" (working tree had uncommitted changes)"
nixpkgs_rev="$(grep -A4 '"nixpkgs": {' manifest/appliance-manifest.json | sed -n 's/.*"rev": "\([0-9a-f]*\)".*/\1/p' | head -1 | cut -c1-12)"
dawo_tag="$(grep -A8 '"dawo_core": {' manifest/appliance-manifest.json | sed -n 's/.*"tag": "\([^"]*\)".*/\1/p' | head -1)"

cat >"${out_dir}/PROVENANCE.md" <<EOF
# Screenshot provenance

Written by \`bash scripts/screenshots.sh\`; do not edit or replace the images
by hand. Every image below was captured by a NixOS VM test of the pinned
configuration — see \`docs/testing.md\`.

- Date: $(date -u +%Y-%m-%dT%H:%MZ)
- Repository: \`${rev}\`${dirty}
- Pins: nixpkgs \`${nixpkgs_rev}\`, DAWO-Core \`${dawo_tag}\` (all: \`manifest/appliance-manifest.json\`)

| Image | Source test | What it shows |
| --- | --- | --- |
| \`installer-plan.png\` | \`test-installer-boot\` | The live ISO's console after \`dawo-appliance-bootstrap plan\`: pinned versions, the twelve steps, no disk writes. |
| \`appliance-desktop.png\` | \`test-appliance-boot\` | The installed host after auto-login: DAWO workplace (KDE Plasma 6) with the welcome dialog. Software-rendered in the test VM, so colours/fonts are as on a machine without GPU acceleration. |
EOF
echo "wrote ${out_dir}/PROVENANCE.md"
