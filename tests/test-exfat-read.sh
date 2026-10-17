#!/usr/bin/env bash
#
# Offline test of tests/exfat-read.py, the read-only exFAT reader that the KVM
# test test-live-launch uses to take the screenshots off its DAWO_LOGS stick
# image (#252). Builds an exFAT image with mkfs.exfat, fills it with
# tests/exfat-add-tree.py (contiguous and fragmented files, directories over
# several clusters, long and non-ASCII names) and checks that the reader gives
# back exactly the files under a prefix, byte for byte, and leaves the image
# untouched.
#
# Needs mkfs.exfat (exfatprogs; `nix shell nixpkgs#exfatprogs`) and python;
# without them the test is skipped.
#
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$(command -v python3 || command -v python || true)"
MKFS="$(command -v mkfs.exfat || true)"
if [[ -z "${PY}" || -z "${MKFS}" ]]; then
  echo "SKIP test-exfat-read: needs python and mkfs.exfat (nix shell nixpkgs#exfatprogs)"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
fails=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { # check DESCRIPTION COMMAND...
  local what="$1"; shift
  if "$@"; then ok "${what}"; else bad "${what}"; fi
}

# The tree: a session directory like the live USB writes, with enough
# screenshots that the directory spans several 4 KiB clusters, files of one
# and of many clusters, and something outside the prefix.
session="dawo-appliance/20261017T101500Z_ab12cd34"
mkdir -p "${work}/seed/${session}/screens" "${work}/seed/dawo-images" "${work}/seed/dawo-appliance/20261016T090000Z_00000000"
for i in $(seq -w 1 60); do
  head -c $((1000 + 997 * 10#${i})) /dev/urandom > "${work}/seed/${session}/screens/20261017T1016${i}.png"
done
head -c 200000 /dev/urandom > "${work}/seed/${session}/screens/launch-cli.png"
echo "LAUNCH-TEST: DONE ok" > "${work}/seed/${session}/launch-selftest.txt"
echo "één omgeving" > "${work}/seed/${session}/naam-met-een-lange-naam-ëñ.txt"
echo "older session" > "${work}/seed/dawo-appliance/20261016T090000Z_00000000/progress.txt"
head -c 50000 /dev/urandom > "${work}/seed/dawo-images/guest.qcow2"
echo marker > "${work}/seed/launch-selftest.txt"

img="${work}/logs.raw"
truncate -s 64M "${img}"
"${MKFS}" -L DAWO_LOGS "${img}" >/dev/null
"${PY}" "${REPO_ROOT}/tests/exfat-add-tree.py" "${img}" 0 "${work}/seed" >/dev/null
before="$(sha256sum < "${img}")"

# 1. Everything.
"${PY}" "${REPO_ROOT}/tests/exfat-read.py" "${img}" 0 "${work}/all" > "${work}/all.txt"
if diff -r "${work}/seed" "${work}/all" >/dev/null; then ok "the whole tree reads back byte for byte"; else bad "the whole tree differs"; fi
check "one line per file (66)" test "$(wc -l < "${work}/all.txt")" -eq 66

# 2. Only the screenshots of one session.
"${PY}" "${REPO_ROOT}/tests/exfat-read.py" "${img}" 0 "${work}/screens" "${session}/screens" >/dev/null
if diff -r "${work}/seed/${session}/screens" "${work}/screens/${session}/screens" >/dev/null; then ok "prefix: the session's screens read back"; else bad "prefix: screens differ"; fi
others="$(cd "${work}/screens" && find . -type f ! -path "./${session}/screens/*" | wc -l)"
check "prefix: nothing outside it (${others} files)" test "${others}" -eq 0

# 3. A prefix naming one file, and one that matches nothing.
"${PY}" "${REPO_ROOT}/tests/exfat-read.py" "${img}" 0 "${work}/one" "${session}/screens/launch-cli.png" >/dev/null
check "prefix naming one file: exactly that file" test "$(find "${work}/one" -type f | wc -l)" -eq 1
check "prefix naming one file: same bytes" cmp -s "${work}/one/${session}/screens/launch-cli.png" "${work}/seed/${session}/screens/launch-cli.png"
"${PY}" "${REPO_ROOT}/tests/exfat-read.py" "${img}" 0 "${work}/none" "no-such-dir" >/dev/null
mkdir -p "${work}/none"
check "a prefix that matches nothing gives nothing" test -z "$(find "${work}/none" -type f)"

# 4. Read-only.
check "the image is unchanged" test "$(sha256sum < "${img}")" = "${before}"
if "${PY}" "${REPO_ROOT}/tests/exfat-read.py" "${work}/seed/launch-selftest.txt" 0 "${work}/x" >/dev/null 2>&1; then
  bad "a file that is not exFAT was accepted"
else
  ok "a file that is not exFAT is refused"
fi

if [[ "${fails}" -ne 0 ]]; then echo "test-exfat-read: ${fails} failure(s)"; exit 1; fi
echo "test-exfat-read: all checks passed"
