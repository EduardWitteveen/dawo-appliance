# The live USB as one disk image (#192): dawo-appliance-live.img, written as
# is by Rufus (DD mode), balenaEtcher or dd. Same layout as the stick tools
# (scripts/write-live-stick.sh, docs/live-usb.md "Writing the stick"):
#   - the live ISO (isohybrid) at byte 0;
#   - MBR partition entry 3: type 0x07, starting 1 MiB after the ISO end
#     rounded up to 1 MiB, with a small, empty exFAT filesystem labelled
#     DAWO_LOGS (seedMiB).
# The first boot grows that seed to the end of the USB disk while it is still
# empty (hosts/appliance/live-data.nix). The image is the ISO + ~seedMiB; the
# exFAT part is mostly zeros, so it compresses well if needed.
#
# Experimental and unofficial. Not for production.
{ pkgs, iso, seedMiB }:

pkgs.runCommand "dawo-appliance-live-img"
{
  nativeBuildInputs = with pkgs; [ coreutils exfatprogs ];
}
  ''
    set -euo pipefail
    E3=478 # MBR partition entry 3 (446 + 2 * 16)
    isofile="$(echo ${iso}/iso/*.iso)"
    rd() { dd if="$1" iflag=skip_bytes,count_bytes skip="$2" count="$3" bs=1M status=none; }
    le32() { printf '\\x%02x\\x%02x\\x%02x\\x%02x' $(($1 & 255)) $((($1 >> 8) & 255)) $((($1 >> 16) & 255)) $((($1 >> 24) & 255)); }

    [ -z "$(rd "$isofile" $E3 16 | od -An -v -tu1 | tr -d ' 0\n')" ] \
      || { echo "MBR entry 3 in the ISO is not empty; it is needed for DAWO_LOGS" >&2; exit 1; }

    len=$(stat -c %s "$isofile")
    start=$(( ((len + 511) / 512 + 2047) / 2048 * 2048 + 2048 ))
    count=$(( ${toString seedMiB} * 2048 ))

    mkdir -p $out/iso
    img=$out/iso/dawo-appliance-live.img
    cp --sparse=always "$isofile" "$img"
    chmod u+w "$img"
    truncate -s $(( (start + count) * 512 )) "$img"

    truncate -s $(( count * 512 )) part.raw
    mkfs.exfat -q -L DAWO_LOGS part.raw >/dev/null
    dd if=part.raw of="$img" bs=1M oflag=seek_bytes seek=$(( start * 512 )) conv=notrunc,sparse status=none
    printf "\\x00\\xfe\\xff\\xff\\x07\\xfe\\xff\\xff$(le32 $start)$(le32 $count)" \
      | dd of="$img" bs=1 seek=$E3 conv=notrunc status=none

    # Checks: entry 3, the exFAT signature and the ISO bytes outside entry 3.
    [ "$(rd "$img" $((E3 + 4)) 1 | od -An -tu1 | tr -d ' \n')" = 7 ]
    [ "$(rd "$img" $((start * 512 + 3)) 8)" = "EXFAT   " ]
    a="$({ rd "$isofile" 0 $E3; rd "$isofile" $((E3 + 16)) $((len - E3 - 16)); } | sha256sum)"
    b="$({ rd "$img" 0 $E3; rd "$img" $((E3 + 16)) $((len - E3 - 16)); } | sha256sum)"
    [ "$a" = "$b" ] || { echo "the image differs from the ISO" >&2; exit 1; }

    chmod a-w "$img"
    (cd $out/iso && sha256sum dawo-appliance-live.img > dawo-appliance-live.img.sha256)
    echo "dawo-appliance-live.img: $(stat -c %s "$img") bytes; DAWO_LOGS seed at sector $start, $count sectors"
  ''
