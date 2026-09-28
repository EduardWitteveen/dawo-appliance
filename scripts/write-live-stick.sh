#!/usr/bin/env bash
#
# write-live-stick.sh — write the DAWO appliance live ISO to a USB stick (or a
# disk image file) with a DAWO_LOGS exFAT partition after the image (#97).
# The Windows equivalent is scripts/windows/dawo-stick.ps1; both produce the
# same layout (docs/live-usb.md, "Writing the stick"):
#
#   - the ISO (isohybrid) raw at offset 0;
#   - MBR partition entry 3: type 0x07, starting 1 MiB after the image end
#     rounded up to 1 MiB, up to the end of the disk, formatted exFAT with the
#     label DAWO_LOGS (the ISO's own entry 3 must be empty).
#
# Usage:
#   bash scripts/write-live-stick.sh --target <device|image> [--iso <path>]
#        [--action plan|write|create] [--confirm-destroy]
#
#   plan    (default) show the target, its MBR entries, whether DAWO_LOGS is
#           present and what write/create would do. Writes nothing.
#   write   write the ISO, keep partition entry 3 and the DAWO_LOGS data.
#           Needs an existing exFAT DAWO_LOGS entry 3 after the image end.
#   create  write the ISO and create a new, empty DAWO_LOGS partition (erases
#           the whole target, including an existing DAWO_LOGS).
#
# write and create need --confirm-destroy (AGENTS.md rule 7). A block device
# must be a whole USB disk (lsblk TRAN=usb) with nothing mounted, at least
# ISO + 1 GiB; writing it needs root (sudo). create needs mkfs.exfat
# (exfatprogs) via scripts/make-dawo-logs-head.sh.
#
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E3=478                  # MBR partition entry 3 (446 + 2 * 16)
HEAD=$((4 * 1024 * 1024)) # the image's first 4 MiB are written last
MIB=$((1024 * 1024))
GIB=$((1024 * MIB))

action=plan
target=""
iso="${HOME}/live-iso/iso/dawo-appliance-live.iso"
confirm=0

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '%s ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }
usage() { sed -n '/^# Usage:/,/^# SPDX/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action) action="${2:-}"; shift 2 ;;
    --target) target="${2:-}"; shift 2 ;;
    --iso) iso="${2:-}"; shift 2 ;;
    --confirm-destroy) confirm=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done
case "${action}" in plan | write | create) ;; *) die "unknown action '${action}' (plan|write|create)" ;; esac
[[ -n "${target}" ]] || die "--target <block device or image file> is required"
if [[ "${action}" != plan && "${confirm}" -ne 1 ]]; then
  die "'${action}' overwrites ${target}; refusing without --confirm-destroy (run --action plan first to see what it would do)"
fi

# --- byte helpers ------------------------------------------------------------
rd() { dd if="$1" iflag=skip_bytes,count_bytes skip="$2" count="$3" bs=1M status=none; }
u8() { rd "$1" "$2" 1 | od -An -tu1 | tr -d ' \n'; }
u32() { rd "$1" "$2" 4 | od -An -tu4 --endian=little | tr -d ' \n'; }
u64() { rd "$1" "$2" 8 | od -An -tu8 --endian=little | tr -d ' \n'; }
le32() { printf '\\x%02x\\x%02x\\x%02x\\x%02x' $(($1 & 255)) $((($1 >> 8) & 255)) $((($1 >> 16) & 255)) $((($1 >> 24) & 255)); }
# Write file <src> into <dst> at byte offset <off>, in place.
put() { dd if="$1" of="$2" bs=4M oflag=seek_bytes seek="$3" conv=notrunc,fsync status=none; }
# sha256 of the first <len> bytes of <file> with the 16 bytes of entry 3 zeroed.
img_hash() {
  { rd "$1" 0 "${E3}"; head -c 16 /dev/zero; rd "$1" $((E3 + 16)) $(($2 - E3 - 16)); } | sha256sum | cut -d' ' -f1
}
# Label of the exFAT filesystem at byte offset <off>, or "" when there is none.
exfat_label() {
  local f="$1" off="$2" bps cs heap root
  [[ "$(rd "${f}" $((off + 3)) 8)" == "EXFAT   " ]] || return 0
  bps=$((1 << $(u8 "${f}" $((off + 108)))))
  cs=$((bps << $(u8 "${f}" $((off + 109)))))
  heap=$(u32 "${f}" $((off + 88)))
  root=$(u32 "${f}" $((off + 96)))
  (( cs <= MIB )) || cs=${MIB}
  # Volume label entry (type 0x83): character count, then UTF-16LE (ASCII here).
  rd "${f}" $((off + heap * bps + (root - 2) * cs)) "${cs}" | od -An -v -tu1 -w32 \
    | awk '$1 == 0 { end = 1 }
           !end && $1 == 131 { s = ""; for (i = 0; i < $2; i++) s = s sprintf("%c", $(3 + 2 * i)); print s; end = 1 }'
}

# --- target ------------------------------------------------------------------
is_dev=0
if [[ -b "${target}" ]]; then
  is_dev=1
  command -v lsblk >/dev/null 2>&1 || die "lsblk not found"
  size=$(blockdev --getsize64 "${target}")
  read -r ttype ttran < <(lsblk -dno TYPE,TRAN "${target}" | awk '{ print $1, ($2 == "" ? "-" : $2) }')
  model=$(lsblk -dno MODEL "${target}" | sed 's/ *$//')
  log "target: block device ${target}: '${model}', transport ${ttran}, type ${ttype}, ${size} bytes ($((size / GIB)) GiB)"
  [[ "${ttype}" == disk ]] || die "${target} is a ${ttype}, not a whole disk"
  [[ "${ttran}" == usb ]] || die "${target} is not a USB disk (transport ${ttran}); refusing"
  if lsblk -nro MOUNTPOINT "${target}" | grep -q .; then
    die "${target} (or one of its partitions) is mounted; unmount it first"
  fi
  [[ -r "${target}" ]] || die "cannot read ${target}; run with sudo"
elif [[ -f "${target}" ]]; then
  size=$(stat -c %s "${target}")
  log "target: image file ${target}: ${size} bytes"
else
  die "target ${target} is neither a block device nor a file"
fi
(( size >= 512 )) || die "target is smaller than one sector"

types=()
log "MBR of the target:"
for k in 0 1 2 3; do
  o=$((446 + 16 * k))
  t=$(u8 "${target}" $((o + 4))); s=$(u32 "${target}" $((o + 8))); c=$(u32 "${target}" $((o + 12)))
  types[k]=${t}
  log "  entry $((k + 1)): type 0x$(printf '%02x' "${t}"), start sector ${s}, ${c} sectors"
done
e3_type=${types[2]}
e3_start=$(u32 "${target}" $((E3 + 8)))
e3_count=$(u32 "${target}" $((E3 + 12)))
logs_label=""
if (( e3_type == 7 && e3_start > 0 && e3_start * 512 + 512 <= size )); then
  logs_label=$(exfat_label "${target}" $((e3_start * 512)))
fi
if [[ "${logs_label}" == DAWO_LOGS ]]; then
  log "DAWO_LOGS: exFAT in entry 3 at byte $((e3_start * 512)), $((e3_count * 512)) bytes"
else
  log "DAWO_LOGS: none (entry 3 has no exFAT filesystem labelled DAWO_LOGS)"
fi

# --- ISO ---------------------------------------------------------------------
iso_ok=0
if [[ -f "${iso}" ]]; then
  iso_len=$(stat -c %s "${iso}")
  iso_sectors=$(((iso_len + 511) / 512))
  new_start=$(((iso_sectors + 2047) / 2048 * 2048 + 2048))
  new_count=$((size / 512 - new_start))
  log "ISO: ${iso}: ${iso_len} bytes"
  iso_ok=1
else
  log "ISO: ${iso} not found"
fi

check_iso() {
  (( iso_ok )) || die "ISO ${iso} not found (--iso <path>)"
  (( iso_len >= HEAD )) || die "the ISO is smaller than 4 MiB; is it the live ISO?"
  if [[ -f "${iso}.sha256" ]]; then
    log "checking the ISO against ${iso}.sha256"
    local want have
    want=$(cut -d' ' -f1 <"${iso}.sha256" | tr 'A-F' 'a-f')
    have=$(sha256sum "${iso}" | cut -d' ' -f1)
    [[ "${want}" == "${have}" ]] || die "the ISO does not match its .sha256; nothing written"
  fi
  [[ "$(rd "${iso}" "${E3}" 16 | od -An -v -tu1 | tr -d ' 0\n')" == "" ]] \
    || die "MBR entry 3 in the ISO is not empty; this tool needs it for DAWO_LOGS"
}
check_size() {
  if (( is_dev )); then
    (( size >= iso_len + GIB )) || die "the stick (${size} bytes) is smaller than the ISO + 1 GiB"
  fi
  (( new_count * 512 >= 64 * MIB )) || die "no room for a DAWO_LOGS partition of at least 64 MiB after the image"
  (( new_count <= 4294967295 )) || die "the target is too large for an MBR partition entry (over 2 TiB)"
}
# Write the ISO: body from 4 MiB on, then the head (with entry 3 = $1, a
# printf %b string) last.
write_iso() {
  log "writing the image from 4 MiB on ($((iso_len - HEAD)) bytes)"
  local progress=none
  (( is_dev )) && progress=progress
  dd if="${iso}" of="${target}" bs=4M skip=1 seek=1 conv=notrunc,fsync status="${progress}"
  rd "${iso}" 0 "${HEAD}" >"${tmp}/head"
  printf '%b' "$1" | dd of="${tmp}/head" bs=1 seek="${E3}" conv=notrunc status=none
  log "writing the first 4 MiB (MBR with entry 3)"
  put "${tmp}/head" "${target}" 0
}
verify_image() {
  log "verifying the image area (sha256 over ${iso_len} bytes, entry 3 excluded)"
  [[ "$(img_hash "${iso}" "${iso_len}")" == "$(img_hash "${target}" "${iso_len}")" ]] \
    || die "VERIFY FAILED: the target differs from the ISO"
}
reread() {
  sync
  if (( is_dev )); then
    blockdev --rereadpt "${target}" 2>/dev/null || partprobe "${target}" 2>/dev/null || true
  fi
}

# --- actions -----------------------------------------------------------------
case "${action}" in
  plan)
    if (( ! iso_ok )); then
      log "plan: no ISO, so nothing to compare; pass --iso <path>"
    else
      if [[ "${logs_label}" == DAWO_LOGS ]] && (( e3_start * 512 >= iso_len )); then
        log "plan: write would overwrite bytes 0..$((iso_len - 1)) with the ISO and keep DAWO_LOGS (entry 3) and its files"
      elif [[ "${logs_label}" == DAWO_LOGS ]]; then
        log "plan: write is not possible: the ISO would overlap DAWO_LOGS at byte $((e3_start * 512)); use create (erases it)"
      else
        log "plan: write is not possible: no DAWO_LOGS; use create"
      fi
      log "plan: create would ERASE the whole target: ISO at 0, DAWO_LOGS (entry 3) at sector ${new_start}, ${new_count} sectors ($((new_count * 512 / MIB)) MiB), new empty exFAT"
    fi
    log "plan: nothing written"
    ;;
  write)
    check_iso
    [[ "${logs_label}" == DAWO_LOGS ]] || die "no exFAT DAWO_LOGS in MBR entry 3 of the target; use --action create; nothing written"
    (( e3_start * 512 >= iso_len )) \
      || die "the ISO (${iso_len} bytes) would overlap DAWO_LOGS at byte $((e3_start * 512)); use --action create; nothing written"
    (( ! is_dev )) || (( size >= iso_len + GIB )) || die "the stick is smaller than the ISO + 1 GiB"
    before=$(rd "${target}" $((e3_start * 512)) "${MIB}" | sha256sum | cut -d' ' -f1)
    log "WILL OVERWRITE bytes 0..$((iso_len - 1)) of ${target} (the current image); DAWO_LOGS at byte $((e3_start * 512)) is kept"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/write-live-stick.XXXXXX")"
    trap 'rm -rf "${tmp}"' EXIT
    write_iso "$(rd "${target}" "${E3}" 16 | od -An -v -tx1 | tr -s ' \n' ' ' | sed 's/ *$//; s/ /\\x/g')"
    reread
    verify_image
    [[ "$(rd "${target}" $((e3_start * 512)) "${MIB}" | sha256sum | cut -d' ' -f1)" == "${before}" ]] \
      || die "VERIFY FAILED: the start of DAWO_LOGS changed"
    log "VERIFY OK: image written, DAWO_LOGS kept"
    ;;
  create)
    check_iso
    check_size
    part_off=$((new_start * 512))
    log "WILL ERASE all of ${target} (${size} bytes)$([[ -n "${logs_label}" ]] && echo ", including the existing ${logs_label} and its files")"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/write-live-stick.XXXXXX")"
    trap 'rm -rf "${tmp}"' EXIT
    log "making the exFAT DAWO_LOGS metadata for ${new_count} sectors"
    bash "${SCRIPT_DIR}/make-dawo-logs-head.sh" $((new_count * 512)) "${tmp}/exfat"
    entry="\\x00\\xfe\\xff\\xff\\x07\\xfe\\xff\\xff$(le32 "${new_start}")$(le32 "${new_count}")"
    write_iso "${entry}"
    exfat_len=$(stat -c %s "${tmp}/exfat")
    log "writing the exFAT metadata (${exfat_len} bytes) at byte ${part_off}"
    put "${tmp}/exfat" "${target}" "${part_off}"
    reread
    verify_image
    [[ "$(u8 "${target}" $((E3 + 4)))" == 7 && "$(u32 "${target}" $((E3 + 8)))" == "${new_start}" \
      && "$(u32 "${target}" $((E3 + 12)))" == "${new_count}" ]] || die "VERIFY FAILED: MBR entry 3"
    [[ "$(rd "${target}" "${part_off}" "${exfat_len}" | sha256sum | cut -d' ' -f1)" \
      == "$(sha256sum "${tmp}/exfat" | cut -d' ' -f1)" ]] || die "VERIFY FAILED: exFAT metadata"
    [[ "$(rd "${target}" $((part_off + 3)) 8)" == "EXFAT   " ]] || die "VERIFY FAILED: no exFAT signature"
    [[ "$(u64 "${target}" $((part_off + 72)))" == "${new_count}" ]] || die "VERIFY FAILED: exFAT volume length"
    log "VERIFY OK: image written, DAWO_LOGS created (entry 3, sector ${new_start}, ${new_count} sectors)"
    ;;
esac
