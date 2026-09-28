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
#
# Stick mode (#118): after a live-USB session on real hardware, take ONE
# debug screenshot from the extracted DAWO_LOGS stick into the README:
#   bash scripts/screenshots.sh --stick <session-dir> <screenshot.png> <dest.png> "<what it shows>"
# <session-dir> is DAWO_LOGS/dawo-appliance/<UTC boot time>_<boot id>/ as
# copied off the stick. The image is only cropped to 16:9 at full height (its
# centre, or CROP_GRAVITY=west|east) and scaled to 1280 px wide, never
# retouched; a row with the
# session, machine model, capture time and the original's SHA-256 goes into
# docs/screenshots/HARDWARE.md (generated; one row per dest image).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
out_dir="docs/screenshots"
mkdir -p "${out_dir}"

if [[ "${1:-}" == "--stick" ]]; then
  session="${2:?session dir}"; shot="${3:?screenshot file name}"; dest="${4:?dest name}"; what="${5:?what it shows}"
  src="${session%/}/screens/${shot}"
  [[ -f "${src}" ]] || { echo "no such screenshot: ${src}" >&2; exit 1; }
  model="$(sed -n '/^== model/{n;N;s/\n/ /;p;q}' "${session%/}/hardware.txt" 2>/dev/null || true)"
  magick_bin="$(nix build --inputs-from "path:${PWD}" nixpkgs#imagemagick --no-link --print-out-paths --no-warn-dirty | tail -n1)/bin/magick"
  read -r w h < <("${magick_bin}" identify -format '%w %h\n' "${src}")
  cw=$(( h * 16 / 9 )); (( cw > w )) && cw="${w}"
  # CROP_GRAVITY=west|east keeps a window that is not in the middle of a
  # wide screen (ImageMagick gravity; default center).
  gravity="${CROP_GRAVITY:-center}"
  [[ "${gravity}" =~ ^(center|west|east)$ ]] || { echo "CROP_GRAVITY must be center, west or east" >&2; exit 1; }
  "${magick_bin}" "${src}" -gravity "${gravity}" -crop "${cw}x${h}+0+0" +repage -resize 1280x -strip "${out_dir}/${dest}"
  chmod 644 "${out_dir}/${dest}"
  echo "==> ${src} (${w}x${h}) → ${out_dir}/${dest} ($(stat -c %s "${out_dir}/${dest}") bytes)"
  hw="${out_dir}/HARDWARE.md"
  if [[ ! -f "${hw}" ]]; then
    cat >"${hw}" <<'EOF'
# Real-hardware screenshots

Written by `bash scripts/screenshots.sh --stick ...`; do not edit or replace
the images by hand. Each image is a debug-mode screenshot that the live USB
saved on its `DAWO_LOGS` stick while running on one of the maintainer's own
test laptops (`docs/live-usb.md`), cropped to its centre and scaled down,
nothing else. Rules: [`README.md`](README.md).

| Image | Machine | Session (UTC boot time_boot id) | Captured (local time) | Original SHA-256 | What it shows |
| --- | --- | --- | --- | --- | --- |
EOF
  fi
  sha="$(sha256sum "${src}" | cut -c1-16)"
  taken="$(basename "${shot}" .png | sed -E 's/^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})$/\1-\2-\3 \4:\5:\6/')"
  row="| \`${dest}\` | ${model:-unknown} | \`$(basename "${session%/}")\` | ${taken} | \`${sha}…\` | ${what} |"
  grep -v "^| \`${dest}\` |" "${hw}" > "${hw}.new" || true
  printf '%s\n' "${row}" >> "${hw}.new"
  mv "${hw}.new" "${hw}"
  exit 0
fi

copy() {
  # copy TEST-ATTR SOURCE-NAME DEST-NAME
  local attr="$1" src="$2" dest="$3" result
  echo "==> ${attr} → ${out_dir}/${dest}"
  result="$(nix build ".#${attr}" --no-link --print-out-paths --no-warn-dirty)"
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
