#!/usr/bin/env bash
#
# Offline test for the live stick tools (#97): scripts/write-live-stick.sh
# (Linux), scripts/windows/dawo-stick.ps1 (Windows; run with every PowerShell
# found: pwsh and/or powershell.exe, also from WSL) and
# scripts/make-dawo-logs-head.sh. Everything runs on disk-image FILES: a
# 128 MiB target and small fake "ISOs" (random data with an MBR whose entries
# 1-2 are set and 3 is empty). No physical disk is opened, no root needed.
#
# Needs mkfs.exfat (exfatprogs; in `nix develop`) for the create/write/read
# cases and python for the read-with-files case; without them those cases
# print SKIP. Runs in Git Bash and in WSL/Linux.
#
# SPDX-License-Identifier: EUPL-1.2
# The checks are strings evaluated by check(), so shellcheck sees neither the
# expansions (SC2016) nor the variables they use (SC2034).
# shellcheck disable=SC2016,SC2034
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LT="${REPO_ROOT}/scripts/write-live-stick.sh"
HEADGEN="${REPO_ROOT}/scripts/make-dawo-logs-head.sh"
PS1="${REPO_ROOT}/scripts/windows/dawo-stick.ps1"
ADDTREE="${REPO_ROOT}/tests/exfat-add-tree.py"

pass=0
fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
skip() { printf '  SKIP %s\n' "$1"; }
dump() { printf '%s\n' "$1" | sed 's/^/      | /'; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; dump "${out:-}"; fi; }

echo "test-live-stick-tool: starting"

in_wsl=0
grep -qi microsoft /proc/version 2>/dev/null && in_wsl=1
PY="$(command -v python3 || command -v python || true)"
MKFS="$(command -v mkfs.exfat || true)"
FSCK="$(command -v fsck.exfat || true)"

# PowerShells to test the Windows tool with.
shells=()
for s in pwsh pwsh.exe powershell.exe; do
  p="$(command -v "${s}" || true)"
  [[ -n "${p}" ]] || continue
  case "${s}" in pwsh.exe) [[ " ${shells[*]:-} " == *" pwsh "* ]] && continue ;; esac
  # pwsh without .exe inside WSL would be a Linux pwsh: it cannot run this.
  [[ "${s}" == pwsh && "${in_wsl}" -eq 1 ]] && continue
  shells+=("${s}")
done
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else wslpath -w "$1"; fi; }

# Work directory; from WSL it must be reachable by Windows PowerShell.
base="${TMPDIR:-/tmp}"
if [[ "${in_wsl}" -eq 1 && ${#shells[@]} -gt 0 ]]; then
  base="$(wslpath -u "$(cd /mnt/c && cmd.exe /c 'echo %TEMP%' 2>/dev/null | tr -d '\r')")"
fi
T="$(mktemp -d "${base}/test-live-stick.XXXXXX")"
trap 'rm -rf "${T}"' EXIT

rd() { dd if="$1" iflag=skip_bytes,count_bytes skip="$2" count="$3" bs=1M status=none; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
region() { rd "$1" "$2" "$3" | sha256sum | cut -d' ' -f1; }
hex16() { rd "$1" 478 16 | od -An -v -tx1 | tr -s ' \n' ' ' | sed 's/^ //; s/ $//'; }
# sha256 of the first <len> bytes with MBR entry 3 zeroed.
img_hash() { { rd "$1" 0 478; head -c 16 /dev/zero; rd "$1" 494 $(($2 - 494)); } | sha256sum | cut -d' ' -f1; }
patch() { printf '%b' "$3" | dd of="$1" bs=1 seek="$2" conv=notrunc status=none; }

# make_iso <file> <MiB>: random data with an isohybrid-like MBR (entries 1-2).
make_iso() {
  head -c $(($2 * 1048576)) /dev/urandom >"$1"
  patch "$1" 446 '\x80\x00\x01\x00\x17\xfe\xff\xff\x00\x00\x00\x00'
  patch "$1" 458 "$(printf '\\x%02x\\x%02x\\x%02x\\x00' $(($2 * 2048 & 255)) $(($2 * 2048 >> 8 & 255)) $(($2 * 2048 >> 16 & 255)))"
  patch "$1" 462 '\x00\xfe\xff\xff\xef\xfe\xff\xff\x40\x00\x00\x00\x00\x20\x00\x00'
  patch "$1" 478 '\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'
  patch "$1" 494 '\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'
  patch "$1" 510 '\x55\xaa'
}
new_target() { rm -f "$1"; truncate -s 128M "$1"; }

make_iso "${T}/a.iso" 20   # the "live ISO"
make_iso "${T}/b.iso" 19   # a newer build (fits before DAWO_LOGS)
make_iso "${T}/c.iso" 24   # too big: would overlap DAWO_LOGS at 21 MiB
make_iso "${T}/d.iso" 20
patch "${T}/d.iso" 482 '\x07'  # entry 3 in use
# 20 MiB = 40960 sectors -> DAWO_LOGS at 40960 + 2048 = 43008 (1 MiB aligned,
# 1 MiB gap), up to the end: 262144 - 43008 = 219136 sectors.
START=43008
COUNT=219136
POFF=$((START * 512))
PLEN=$((COUNT * 512))
WANT_E3="00 fe ff ff 07 fe ff ff 00 a8 00 00 00 58 03 00"

# The tree the appliance would have written, for the read case.
mkdir -p "${T}/src/dawo-appliance/2026-09-28_1200_ab12/screens" "${T}/src/dawo-images"
head -c 40000 /dev/urandom | base64 >"${T}/src/dawo-appliance/2026-09-28_1200_ab12/journal.txt"
echo "desktop 20" >"${T}/src/dawo-appliance/2026-09-28_1200_ab12/progress.txt"
head -c 30000 /dev/urandom >"${T}/src/dawo-appliance/2026-09-28_1200_ab12/screens/shot-0001.png"
head -c 20000 /dev/urandom >"${T}/src/dawo-appliance/2026-09-28_1200_ab12/screens/shot-0002.png"
head -c 9000 /dev/urandom | base64 >"${T}/src/dawo-appliance/2026-09-28_1200_ab12/hardware-information.txt"
head -c 8192 /dev/urandom >"${T}/src/dawo-data.ext4"
head -c 8192 /dev/urandom >"${T}/src/dawo-images/guest.qcow2"

# =============================================================================
echo "  -- Linux: scripts/write-live-stick.sh --"
tgt="${T}/linux.img"
new_target "${tgt}"
h0="$(sha "${tgt}")"

out="$(bash "${LT}" --target "${tgt}" --iso "${T}/a.iso" 2>&1)" && rc=0 || rc=$?
check "plan: exit 0" '[[ ${rc} -eq 0 ]]'
check "plan: writes nothing" '[[ "$(sha "${tgt}")" == "${h0}" ]]'
check "plan: reports no DAWO_LOGS and the create layout (sector ${START}, ${COUNT} sectors)" \
  '[[ "${out}" == *"DAWO_LOGS: none"* && "${out}" == *"sector ${START}, ${COUNT} sectors"* ]]'

for a in write create; do
  out="$(bash "${LT}" --action "${a}" --target "${tgt}" --iso "${T}/a.iso" 2>&1)" && rc=0 || rc=$?
  check "${a} without --confirm-destroy refuses, nothing written" \
    '[[ ${rc} -ne 0 && "${out}" == *"--confirm-destroy"* && "$(sha "${tgt}")" == "${h0}" ]]'
done
out="$(bash "${LT}" --action write --confirm-destroy --target "${tgt}" --iso "${T}/a.iso" 2>&1)" && rc=0 || rc=$?
check "write on a target without DAWO_LOGS refuses, nothing written" \
  '[[ ${rc} -ne 0 && "${out}" == *"no exFAT DAWO_LOGS"* && "$(sha "${tgt}")" == "${h0}" ]]'
out="$(bash "${LT}" --action nonsense --target "${tgt}" 2>&1)" && rc=0 || rc=$?
check "unknown action refuses" '[[ ${rc} -ne 0 ]]'

linux_created=""
if [[ -z "${MKFS}" ]]; then
  skip "Linux create/write and make-dawo-logs-head (mkfs.exfat not found; run in 'nix develop')"
else
  out="$(bash "${HEADGEN}" "${PLEN}" "${T}/head.bin" 2>&1)" && rc=0 || rc=$?
  hl=$(stat -c %s "${T}/head.bin" 2>/dev/null || echo 0)
  check "make-dawo-logs-head: exFAT head of >= 32 MiB, 1 MiB multiple, volume length ${COUNT}" \
    '[[ ${rc} -eq 0 && ${hl} -ge 33554432 && $((hl % 1048576)) -eq 0 && "$(rd "${T}/head.bin" 3 8)" == "EXFAT   " && "$(rd "${T}/head.bin" 72 8 | od -An -tu8 --endian=little | tr -d " \n")" == "${COUNT}" ]]'
  out="$(bash "${HEADGEN}" 1000 "${T}/x.bin" 2>&1)" && rc=0 || rc=$?
  check "make-dawo-logs-head: refuses a size that is not a multiple of 512" '[[ ${rc} -ne 0 ]]'

  out="$(bash "${LT}" --action create --confirm-destroy --target "${tgt}" --iso "${T}/d.iso" 2>&1)" && rc=0 || rc=$?
  check "create refuses an ISO whose MBR entry 3 is in use, nothing written" \
    '[[ ${rc} -ne 0 && "${out}" == *"entry 3 in the ISO"* && "$(sha "${tgt}")" == "${h0}" ]]'

  out="$(bash "${LT}" --action create --confirm-destroy --target "${tgt}" --iso "${T}/a.iso" 2>&1)" && rc=0 || rc=$?
  check "create: exit 0 and VERIFY OK" '[[ ${rc} -eq 0 && "${out}" == *"VERIFY OK"* ]]'
  check "create: MBR entry 3 = type 0x07, sector ${START}, ${COUNT} sectors" '[[ "$(hex16 "${tgt}")" == "${WANT_E3}" ]]'
  check "create: exFAT signature at the partition" '[[ "$(rd "${tgt}" $((POFF + 3)) 8)" == "EXFAT   " ]]'
  check "create: image area equals the ISO (entry 3 excluded)" '[[ "$(img_hash "${tgt}" $((20 * 1048576)))" == "$(img_hash "${T}/a.iso" $((20 * 1048576)))" ]]'
  check "create: gap between image and partition is zero" '[[ "$(rd "${tgt}" $((20 * 1048576)) 1048576 | tr -d "\\0" | wc -c)" -eq 0 ]]'
  linux_created="$(region "${tgt}" 0 "${POFF}")"
  if [[ -n "${FSCK}" ]]; then
    rd "${tgt}" "${POFF}" "${PLEN}" >"${T}/part.img"
    out="$("${FSCK}" -n "${T}/part.img" 2>&1)" && rc=0 || rc=$?
    check "create: fsck.exfat finds DAWO_LOGS clean" '[[ ${rc} -eq 0 ]]'
    rm -f "${T}/part.img"
  else
    skip "fsck.exfat not found"
  fi

  out="$(bash "${LT}" --target "${tgt}" --iso "${T}/b.iso" 2>&1)" && rc=0 || rc=$?
  check "plan after create: DAWO_LOGS present, write would keep it" \
    '[[ ${rc} -eq 0 && "${out}" == *"DAWO_LOGS: exFAT in entry 3"* && "${out}" == *"keep DAWO_LOGS"* ]]'

  if [[ -n "${PY}" ]]; then
    "${PY}" "${ADDTREE}" "${tgt}" "${POFF}" "${T}/src" >/dev/null
  fi
  e3="$(hex16 "${tgt}")"
  hp="$(region "${tgt}" "${POFF}" "${PLEN}")"
  out="$(bash "${LT}" --action write --confirm-destroy --target "${tgt}" --iso "${T}/b.iso" 2>&1)" && rc=0 || rc=$?
  check "write of a newer ISO: exit 0 and VERIFY OK" '[[ ${rc} -eq 0 && "${out}" == *"VERIFY OK"* ]]'
  check "write: MBR entry 3 unchanged" '[[ "$(hex16 "${tgt}")" == "${e3}" ]]'
  check "write: the whole DAWO_LOGS partition unchanged (exFAT head and files)" '[[ "$(region "${tgt}" "${POFF}" "${PLEN}")" == "${hp}" ]]'
  check "write: image area equals the new ISO" '[[ "$(img_hash "${tgt}" $((19 * 1048576)))" == "$(img_hash "${T}/b.iso" $((19 * 1048576)))" ]]'

  h1="$(sha "${tgt}")"
  out="$(bash "${LT}" --action write --confirm-destroy --target "${tgt}" --iso "${T}/c.iso" 2>&1)" && rc=0 || rc=$?
  check "write refuses an ISO that would overlap DAWO_LOGS, nothing written" \
    '[[ ${rc} -ne 0 && "${out}" == *"overlap"* && "$(sha "${tgt}")" == "${h1}" ]]'
  cp "${T}/b.iso" "${T}/e.iso"
  echo "0000000000000000000000000000000000000000000000000000000000000000  e.iso" >"${T}/e.iso.sha256"
  out="$(bash "${LT}" --action write --confirm-destroy --target "${tgt}" --iso "${T}/e.iso" 2>&1)" && rc=0 || rc=$?
  check "write refuses an ISO that does not match its .sha256, nothing written" \
    '[[ ${rc} -ne 0 && "${out}" == *".sha256"* && "$(sha "${tgt}")" == "${h1}" ]]'
fi

# =============================================================================
if [[ ${#shells[@]} -eq 0 ]]; then
  echo "  -- Windows: scripts/windows/dawo-stick.ps1 --"
  skip "dawo-stick.ps1 (no pwsh or powershell.exe here)"
fi
for shell in "${shells[@]}"; do
  echo "  -- Windows: scripts/windows/dawo-stick.ps1 with ${shell} --"
  runps() { MSYS_NO_PATHCONV=1 "${shell}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(winpath "${PS1}")" "$@" 2>&1 | tr -d '\r'; }
  tgt="${T}/win-${shell%.exe}.img"
  new_target "${tgt}"
  h0="$(sha "${tgt}")"
  W_TGT="$(winpath "${tgt}")"
  W_A="$(winpath "${T}/a.iso")"

  out="$(runps -ImagePath "${W_TGT}" -Iso "${W_A}")" && rc=0 || rc=$?
  check "plan: exit 0, writes nothing, shows the create layout" \
    '[[ ${rc} -eq 0 && "$(sha "${tgt}")" == "${h0}" && "${out}" == *"DAWO_LOGS: none"* && "${out}" == *"sector ${START}, ${COUNT} sectors"* ]]'
  for a in write create; do
    out="$(runps -Action "${a}" -ImagePath "${W_TGT}" -Iso "${W_A}")" && rc=0 || rc=$?
    check "${a} without -ConfirmDestroy refuses, nothing written" \
      '[[ ${rc} -ne 0 && "${out}" == *"-ConfirmDestroy"* && "$(sha "${tgt}")" == "${h0}" ]]'
  done
  out="$(runps -DiskNumber 99 -ImagePath "${W_TGT}")" && rc=0 || rc=$?
  check "both -DiskNumber and -ImagePath refuses" '[[ ${rc} -ne 0 && "${out}" == *"exactly one"* ]]'
  out="$(runps -Action plan)" && rc=0 || rc=$?
  check "neither -DiskNumber nor -ImagePath refuses" '[[ ${rc} -ne 0 && "${out}" == *"exactly one"* ]]'
  out="$(runps -Action write -ConfirmDestroy -ImagePath "${W_TGT}" -Iso "${W_A}")" && rc=0 || rc=$?
  check "write on a target without DAWO_LOGS refuses, nothing written" \
    '[[ ${rc} -ne 0 && "${out}" == *"no exFAT DAWO_LOGS"* && "$(sha "${tgt}")" == "${h0}" ]]'
  out="$(runps -Action read -ImagePath "${W_TGT}" -OutDir "$(winpath "${T}")\\none")" && rc=0 || rc=$?
  check "read on a target without DAWO_LOGS fails cleanly" '[[ ${rc} -ne 0 && "${out}" == *"no exFAT DAWO_LOGS"* ]]'

  if [[ ! -f "${T}/head.bin" ]]; then
    skip "create/write/read with ${shell} (no -ExfatHead: mkfs.exfat not found; run in WSL with 'nix develop')"
    continue
  fi
  bash "${HEADGEN}" $((PLEN - 1048576)) "${T}/wrong.bin" >/dev/null
  out="$(runps -Action create -ConfirmDestroy -ImagePath "${W_TGT}" -Iso "${W_A}" -ExfatHead "$(winpath "${T}/wrong.bin")")" && rc=0 || rc=$?
  check "create refuses an -ExfatHead made for another partition size, nothing written" \
    '[[ ${rc} -ne 0 && "${out}" == *"make-dawo-logs-head.sh ${PLEN}"* && "$(sha "${tgt}")" == "${h0}" ]]'

  out="$(runps -Action create -ConfirmDestroy -ImagePath "${W_TGT}" -Iso "${W_A}" -ExfatHead "$(winpath "${T}/head.bin")")" && rc=0 || rc=$?
  check "create: exit 0 and VERIFY OK" '[[ ${rc} -eq 0 && "${out}" == *"VERIFY OK"* ]]'
  check "create: MBR entry 3 = type 0x07, sector ${START}, ${COUNT} sectors" '[[ "$(hex16 "${tgt}")" == "${WANT_E3}" ]]'
  check "create: exFAT signature at the partition, head written as given" \
    '[[ "$(rd "${tgt}" $((POFF + 3)) 8)" == "EXFAT   " && "$(region "${tgt}" "${POFF}" "$(stat -c %s "${T}/head.bin")")" == "$(sha "${T}/head.bin")" ]]'
  check "create: image area equals the ISO (entry 3 excluded)" '[[ "$(img_hash "${tgt}" $((20 * 1048576)))" == "$(img_hash "${T}/a.iso" $((20 * 1048576)))" ]]'
  if [[ -n "${linux_created}" ]]; then
    check "create: same bytes before DAWO_LOGS as the Linux tool" '[[ "$(region "${tgt}" 0 "${POFF}")" == "${linux_created}" ]]'
  fi

  hr="$(sha "${tgt}")"
  out="$(runps -Action read -ImagePath "${W_TGT}" -OutDir "$(winpath "${T}")\\empty-out")" && rc=0 || rc=$?
  check "read on an empty DAWO_LOGS: clean 'no dawo-appliance folder' error" \
    '[[ ${rc} -ne 0 && "${out}" == *"no dawo-appliance folder"* && "$(sha "${tgt}")" == "${hr}" ]]'

  if [[ -n "${PY}" ]]; then
    "${PY}" "${ADDTREE}" "${tgt}" "${POFF}" "${T}/src" >/dev/null
    if [[ -n "${FSCK}" ]]; then
      rd "${tgt}" "${POFF}" "${PLEN}" >"${T}/part.img"
      out="$("${FSCK}" -n "${T}/part.img" 2>&1)" && rc=0 || rc=$?
      check "test fixture: DAWO_LOGS with files is a clean exFAT (fsck.exfat)" '[[ ${rc} -eq 0 ]]'
      rm -f "${T}/part.img"
    fi
    hr="$(sha "${tgt}")"
    rm -rf "${T}/out"
    out="$(runps -Action read -ImagePath "${W_TGT}" -OutDir "$(winpath "${T}")\\out")" && rc=0 || rc=$?
    check "read: exit 0, target unchanged" '[[ ${rc} -eq 0 && "$(sha "${tgt}")" == "${hr}" ]]'
    check "read: dawo-appliance/ copied exactly (contiguous and fragmented files)" \
      'diff -r "${T}/src/dawo-appliance" "${T}/out" >/dev/null'
    check "read: dawo-data.ext4 and dawo-images/ not copied" '[[ ! -e "${T}/out/dawo-data.ext4" && ! -e "${T}/out/dawo-images" ]]'
  else
    skip "read with files (python not found)"
  fi

  e3="$(hex16 "${tgt}")"
  hp="$(region "${tgt}" "${POFF}" "${PLEN}")"
  out="$(runps -Action write -ConfirmDestroy -ImagePath "${W_TGT}" -Iso "$(winpath "${T}/b.iso")")" && rc=0 || rc=$?
  check "write of a newer ISO: exit 0 and VERIFY OK" '[[ ${rc} -eq 0 && "${out}" == *"VERIFY OK"* ]]'
  check "write: MBR entry 3 unchanged" '[[ "$(hex16 "${tgt}")" == "${e3}" ]]'
  check "write: the whole DAWO_LOGS partition unchanged" '[[ "$(region "${tgt}" "${POFF}" "${PLEN}")" == "${hp}" ]]'
  check "write: image area equals the new ISO" '[[ "$(img_hash "${tgt}" $((19 * 1048576)))" == "$(img_hash "${T}/b.iso" $((19 * 1048576)))" ]]'
  h1="$(sha "${tgt}")"
  out="$(runps -Action write -ConfirmDestroy -ImagePath "${W_TGT}" -Iso "$(winpath "${T}/c.iso")")" && rc=0 || rc=$?
  check "write refuses an ISO that would overlap DAWO_LOGS, nothing written" \
    '[[ ${rc} -ne 0 && "${out}" == *"overlap"* && "$(sha "${tgt}")" == "${h1}" ]]'
  if [[ -f "${T}/e.iso.sha256" ]]; then
    out="$(runps -Action write -ConfirmDestroy -ImagePath "${W_TGT}" -Iso "$(winpath "${T}/e.iso")")" && rc=0 || rc=$?
    check "write refuses an ISO that does not match its .sha256, nothing written" \
      '[[ ${rc} -ne 0 && "${out}" == *".sha256"* && "$(sha "${tgt}")" == "${h1}" ]]'
  fi
done

echo
echo "test-live-stick-tool: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
