# The live disk image written as is, the way Rufus (DD mode) or Etcher write
# it (#192): dawo-appliance-live.img copied to the start of a 48 GiB USB disk
# (sparse file), nothing else. Boots it TWICE next to a patterned internal
# disk:
#   boot 1: the small, empty DAWO_LOGS of the image is grown to the end of the
#           USB disk and the data is created on it ("data: stick: created",
#           "grown")
#   boot 2: the grown DAWO_LOGS is reused as is ("data: stick: reused"), not
#           grown or formatted again
# and afterwards: MBR entry 3 and the exFAT volume span the rest of the disk,
# the image area is unchanged apart from entry 3, and the internal disk is
# byte-for-byte unchanged.
#
# Each boot stops once the data line is reported (the guest and K3s are
# covered by test-live-iso-boot and test-live-iso-persist). Needs KVM.
{ pkgs, img }:

pkgs.runCommand "live-img-grow"
{
  requiredSystemFeatures = [ "kvm" ];
  nativeBuildInputs = with pkgs; [ qemu_kvm coreutils gnugrep socat ];
}
  ''
    set -euo pipefail
    imgfile=${img}/iso/dawo-appliance-live.img
    E3=478

    rd() { dd if="$1" iflag=skip_bytes,count_bytes skip="$2" count="$3" bs=1M status=none; }
    u32() { rd "$1" "$2" 4 | od -An -tu4 --endian=little | tr -d ' \n'; }
    u64() { rd "$1" "$2" 8 | od -An -tu8 --endian=little | tr -d ' \n'; }
    # sha256 of the first <len> bytes with the 16 bytes of entry 3 zeroed.
    img_hash() {
      { rd "$1" 0 "$E3"; head -c 16 /dev/zero; rd "$1" $((E3 + 16)) $(($2 - E3 - 16)); } | sha256sum | cut -d' ' -f1
    }

    { yes DAWO-INTERNAL-DISK-MUST-STAY-UNTOUCHED || true; } | head -c 1073741824 > internal.raw
    before="$(sha256sum < internal.raw)"

    # "Rufus": the image at byte 0 of a larger USB disk, the rest unallocated.
    cp --sparse=always "$imgfile" stick.raw
    chmod u+w stick.raw
    truncate -s 48G stick.raw
    size=$(stat -c %s stick.raw)
    img_len=$(stat -c %s "$imgfile")
    start=$(u32 stick.raw $((E3 + 8)))
    seed=$(u32 stick.raw $((E3 + 12)))
    echo "image: $img_len bytes; DAWO_LOGS seed at sector $start, $seed sectors; disk $size bytes"
    # Everything before DAWO_LOGS: the ISO and the gap after it.
    img_before="$(img_hash stick.raw $((start * 512)))"

    cp ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd vars.fd
    chmod u+w vars.fd

    boot() {
      n="$1"
      rm -f "qmp$n.sock" "qemu$n.pid"
      qemu-system-x86_64 \
        -enable-kvm -cpu host -machine q35 -m 12288 -smp 6 \
        -drive if=pflash,format=raw,readonly=on,file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd \
        -drive if=pflash,format=raw,file=vars.fd \
        -device qemu-xhci -drive if=none,id=stick,format=raw,file=stick.raw \
        -device usb-storage,drive=stick,bootindex=1 \
        -drive if=virtio,format=raw,file=internal.raw \
        -nic user,model=virtio \
        -display none -serial "file:serial$n.log" -monitor none \
        -qmp "unix:qmp$n.sock,server=on,wait=off" \
        -pidfile "qemu$n.pid" -daemonize
      SECONDS=0
      result=timeout
      while [ "$SECONDS" -lt 900 ]; do
        if grep -a -q "DAWO-LIVE: data:" "serial$n.log"; then result=ok; break; fi
        if ! kill -0 "$(cat "qemu$n.pid" 2>/dev/null)" 2>/dev/null; then result=qemu-exited; break; fi
        sleep 5
      done
      echo "=== boot $n: $result after ''${SECONDS}s ==="
      grep -a "DAWO-LIVE:\|dawo-appliance-data-setup" "serial$n.log" | tr -d '\r' || true
      # Clean shutdown, so the exFAT filesystem is consistent for boot 2.
      printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"system_powerdown"}' \
        | socat - "UNIX-CONNECT:qmp$n.sock" >/dev/null 2>&1 || true
      SECONDS=0
      down=no
      for _ in $(seq 1 120); do
        if ! kill -0 "$(cat "qemu$n.pid" 2>/dev/null)" 2>/dev/null; then down=yes; break; fi
        sleep 2
      done
      echo "boot $n: shutdown took ''${SECONDS}s (clean: $down)"
      kill "$(cat "qemu$n.pid" 2>/dev/null)" 2>/dev/null || true
      sleep 2
      if [ "$result" != ok ]; then
        echo "FAIL: boot $n: $result; last console lines:"
        tail -n 60 "serial$n.log" | tr -d '\r' || true
        exit 1
      fi
      [ "$down" = yes ] || { echo "FAIL: boot $n: no clean power-off within 240 s"; exit 1; }
    }

    boot 1
    grep -a "DAWO-LIVE: data:" serial1.log | grep -q "stick: created" \
      || { echo "FAIL: boot 1 did not create the data on the stick"; exit 1; }
    grep -a "DAWO-LIVE: data:" serial1.log | grep -q "grown" \
      || { echo "FAIL: boot 1 did not grow DAWO_LOGS"; exit 1; }

    want=$((size / 512 - start))
    [ "$(u32 stick.raw $((E3 + 8)))" = "$start" ] || { echo "FAIL: entry 3 moved"; exit 1; }
    [ "$(u32 stick.raw $((E3 + 12)))" = "$want" ] \
      || { echo "FAIL: entry 3 has $(u32 stick.raw $((E3 + 12))) sectors, want $want"; exit 1; }
    [ "$(rd stick.raw $((start * 512 + 3)) 8)" = "EXFAT   " ] || { echo "FAIL: no exFAT at DAWO_LOGS"; exit 1; }
    [ "$(u64 stick.raw $((start * 512 + 72)))" = "$want" ] \
      || { echo "FAIL: the exFAT volume has $(u64 stick.raw $((start * 512 + 72))) sectors, want $want"; exit 1; }
    echo "DAWO_LOGS grown: $seed -> $want sectors"

    boot 2
    grep -a "DAWO-LIVE: data:" serial2.log | grep -q "stick: reused" \
      || { echo "FAIL: boot 2 did not reuse the data on the grown DAWO_LOGS"; exit 1; }
    if grep -a "DAWO-LIVE: data:" serial2.log | grep -q "grown"; then
      echo "FAIL: boot 2 grew DAWO_LOGS again"; exit 1
    fi
    [ "$(u32 stick.raw $((E3 + 12)))" = "$want" ] || { echo "FAIL: entry 3 changed on boot 2"; exit 1; }

    [ "$(img_hash stick.raw $((start * 512)))" = "$img_before" ] \
      || { echo "FAIL: the image area changed (apart from entry 3)"; exit 1; }
    echo "image area unchanged apart from entry 3"

    after="$(sha256sum < internal.raw)"
    [ "$before" = "$after" ] || { echo "FAIL: the internal disk was modified"; exit 1; }
    echo "internal disk unchanged"

    mkdir -p $out
    for n in 1 2; do grep -a "DAWO-LIVE:" "serial$n.log" | tr -d '\r' | sed "s/^/boot $n: /"; done > $out/report.txt
    echo "dawo-logs: $seed -> $want sectors" >> $out/report.txt
    echo "internal-disk=unchanged" >> $out/report.txt
  ''
