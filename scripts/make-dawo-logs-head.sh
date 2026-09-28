#!/usr/bin/env bash
#
# make-dawo-logs-head.sh — make the exFAT metadata ("head") for the DAWO_LOGS
# partition of the live stick (#97, docs/live-usb.md "Writing the stick").
#
#   bash scripts/make-dawo-logs-head.sh <partition-size-bytes> <out-file>
#
# Runs `mkfs.exfat -L DAWO_LOGS` on a sparse temporary file of exactly the
# partition size and copies the part of it that mkfs wrote (boot regions, FAT,
# allocation bitmap, up-case table, root directory; at least 32 MiB, rounded up
# to 1 MiB) to <out-file>. Writing that file at the partition offset gives the
# same filesystem as formatting the partition itself. Windows cannot format
# the partition (it does not mount it), so on Windows run this in WSL and pass
# the file to `scripts/windows/dawo-stick.ps1 -Action create -ExfatHead`.
# `scripts/write-live-stick.sh --action create` uses it too.
#
# Needs mkfs.exfat (exfatprogs; in the repo's `nix develop` shell). Writes
# only <out-file> and a temporary file; no root needed.
#
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail

die() { echo "make-dawo-logs-head: ERROR: $*" >&2; exit 1; }

[[ $# -eq 2 ]] || die "usage: $0 <partition-size-bytes> <out-file>"
size="$1"
out="$2"
[[ "${size}" =~ ^[0-9]+$ ]] || die "partition size must be a number of bytes: ${size}"
(( size % 512 == 0 )) || die "partition size must be a multiple of 512: ${size}"
min=$((64 * 1024 * 1024))
(( size >= min )) || die "partition size ${size} is below the minimum of ${min} bytes"
command -v mkfs.exfat >/dev/null 2>&1 \
  || die "mkfs.exfat not found (install exfatprogs, or use 'nix develop' in this repo)"

# Read <count> bytes at byte offset <off> of <file>.
rd() { dd if="$1" iflag=skip_bytes,count_bytes skip="$2" count="$3" bs=1M status=none; }
u8() { rd "$1" "$2" 1 | od -An -tu1 | tr -d ' \n'; }
u32() { rd "$1" "$2" 4 | od -An -tu4 --endian=little | tr -d ' \n'; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/dawo-logs-head.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT
img="${tmp}/part.img"
truncate -s "${size}" "${img}"
mkfs.exfat -q -L DAWO_LOGS "${img}" >/dev/null || die "mkfs.exfat failed"

[[ "$(rd "${img}" 3 8)" == "EXFAT   " ]] || die "mkfs.exfat did not write an exFAT boot sector"
bps=$((1 << $(u8 "${img}" 108)))
cs=$((bps << $(u8 "${img}" 109)))
heap=$(($(u32 "${img}" 88) * bps))
root=$(u32 "${img}" 96)

# The highest cluster in use, from the allocation bitmap (its directory entry,
# type 0x81, is in the first root directory cluster).
root_off=$((heap + (root - 2) * cs))
bitmap=$(rd "${img}" "${root_off}" "${cs}" | od -An -v -tu4 --endian=little -w32 \
  | awk '!found && ($1 % 256) == 129 { print $6, $7; found = 1 }')
[[ -n "${bitmap}" ]] || die "no allocation bitmap entry in the root directory"
read -r bm_cluster bm_len <<<"${bitmap}"
last=$(rd "${img}" $((heap + (bm_cluster - 2) * cs)) "${bm_len}" | od -An -v -tu1 -w1 \
  | awk '$1 != 0 { i = NR - 1; v = $1 } END { b = 0; while (v > 1) { v = int(v / 2); b++ } print i * 8 + b }')
used_end=$((heap + (last + 1) * cs))

mib=$((1024 * 1024))
head_len=$(((used_end + mib - 1) / mib * mib))
(( head_len >= 32 * mib )) || head_len=$((32 * mib))
(( head_len <= size )) || head_len=${size}

rd "${img}" 0 "${head_len}" >"${out}"
echo "make-dawo-logs-head: wrote ${out}: ${head_len} bytes of exFAT 'DAWO_LOGS' for a partition of ${size} bytes (cluster ${cs}, metadata ends at ${used_end})"
