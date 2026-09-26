# Boots the REAL live USB image (ADR 0006, #93) in QEMU, the way a laptop
# would: UEFI firmware, the ISO as a USB stick, and a separate "internal disk"
# filled with a known pattern. Passes when the image's own report service
# prints `DAWO-LIVE: ... DONE ok` on the serial console (desktop up, guest
# reachable, K3s node Ready) AND the internal disk is byte-for-byte unchanged
# AND the same report reached a second USB stick labelled DAWO_LOGS (the debug
# logs the maintainer hands back, hosts/appliance/live-logs.nix).
#
# Not a runNixOSTest: those boot a test build of the modules, not the image a
# user writes to a stick. This test boots exactly `.#appliance-live-iso`.
#
# Needs KVM (nested: the live system runs the Ubuntu guest). Offline: the
# pinned cloud image and K3s artifacts are on the image.
{ pkgs, iso }:

pkgs.runCommand "live-iso-boot"
{
  requiredSystemFeatures = [ "kvm" ];
  nativeBuildInputs = with pkgs; [ qemu_kvm coreutils gnugrep dosfstools mtools socat ];
}
  ''
    set -euo pipefail
    isofile="$(echo ${iso}/iso/*.iso)"

    # The laptop's internal disk: 1 GiB with a recognisable pattern.
    { yes DAWO-INTERNAL-DISK-MUST-STAY-UNTOUCHED || true; } | head -c 1073741824 > internal.raw
    before="$(sha256sum < internal.raw)"

    # The debug-log stick the user formatted as DAWO_LOGS (FAT32).
    truncate -s 512M logs.raw
    mkfs.vfat -F 32 -n DAWO_LOGS logs.raw

    cp ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd vars.fd
    chmod u+w vars.fd

    SECONDS=0
    qemu-system-x86_64 \
      -enable-kvm -cpu host -machine q35 -m 14336 -smp 6 \
      -drive if=pflash,format=raw,readonly=on,file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd \
      -drive if=pflash,format=raw,file=vars.fd \
      -device qemu-xhci -drive if=none,id=stick,format=raw,readonly=on,file="$isofile" \
      -device usb-storage,drive=stick,bootindex=1 \
      -drive if=none,id=logs,format=raw,file=logs.raw \
      -device usb-storage,drive=logs \
      -drive if=virtio,format=raw,file=internal.raw \
      -nic user,model=virtio \
      -display none -serial file:serial.log -monitor none \
      -qmp unix:qmp.sock,server=on,wait=off \
      -pidfile qemu.pid -daemonize

    result=timeout
    while [ "$SECONDS" -lt 2400 ]; do
      if grep -a -q "DAWO-LIVE: DONE ok" serial.log; then result=ok; break; fi
      if grep -a -q "DAWO-LIVE: DONE fail" serial.log; then result=fail; break; fi
      if ! kill -0 "$(cat qemu.pid)" 2>/dev/null; then result=qemu-exited; break; fi
      sleep 5
    done
    # Let the 30 s log timer copy the final report, then shut down cleanly
    # (which also runs the shutdown copy); kill only as a fallback.
    sleep 45
    printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"system_powerdown"}' \
      | socat - UNIX-CONNECT:qmp.sock >/dev/null 2>&1 || true
    for _ in $(seq 1 60); do kill -0 "$(cat qemu.pid)" 2>/dev/null || break; sleep 2; done
    kill "$(cat qemu.pid)" 2>/dev/null || true
    sleep 3

    echo "=== DAWO-LIVE lines (result: $result after ''${SECONDS}s) ==="
    grep -a "DAWO-LIVE:" serial.log || true

    after="$(sha256sum < internal.raw)"
    if [ "$before" != "$after" ]; then
      echo "FAIL: the internal disk was modified"
      exit 1
    fi
    echo "internal disk unchanged"

    echo "=== DAWO_LOGS stick ==="
    mdir -/ -i logs.raw ::/dawo-appliance || true
    run="$(mdir -b -i logs.raw ::/dawo-appliance 2>/dev/null | head -n1)"
    logs_ok=no
    if [ -n "$run" ]; then
      mcopy -n -i logs.raw "$run/progress.txt" progress.txt 2>/dev/null || true
      mcopy -n -i logs.raw "$run/journal.txt" journal.txt 2>/dev/null || true
      if grep -q "DAWO-LIVE: DONE ok" progress.txt 2>/dev/null && [ -s journal.txt ]; then logs_ok=yes; fi
    fi
    echo "logs on stick: $logs_ok"

    if [ "$result" != ok ]; then
      echo "FAIL: live boot result: $result; last console lines:"
      tail -n 60 serial.log | tr -d '\r' || true
      exit 1
    fi

    if [ "$logs_ok" != yes ]; then
      echo "FAIL: the report did not reach the DAWO_LOGS stick"
      exit 1
    fi

    mkdir -p $out
    grep -a "DAWO-LIVE:" serial.log | tr -d '\r' > $out/report.txt
    echo "result=$result seconds=$SECONDS internal-disk=unchanged logs-on-stick=$logs_ok" >> $out/report.txt
  ''
