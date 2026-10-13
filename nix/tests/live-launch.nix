# The Launcher flow as a regression run (ADR 0008, #229): boots the REAL live
# image with a 48 GiB exFAT DAWO_LOGS stick that carries launch-selftest.txt
# and nothing to start at boot. The image's own self-test
# (hosts/appliance/live-launch-selftest.nix) then goes through the Launcher's
# API the way the buttons do: a clean boot with nothing running, Starten (K3s
# Ready), Stoppen (guest down), and the same once more. Passes on
# `LAUNCH-TEST: DONE ok` and an untouched internal disk.
#
# Needs KVM (nested guest). Offline, like test-live-iso-boot.
{ pkgs, iso }:

pkgs.runCommand "live-launch"
{
  requiredSystemFeatures = [ "kvm" ];
  nativeBuildInputs = with pkgs; [ qemu_kvm coreutils gnugrep exfatprogs socat python3 ];
}
  ''
    set -euo pipefail
    isofile="$(echo ${iso}/iso/*.iso)"

    { yes DAWO-INTERNAL-DISK-MUST-STAY-UNTOUCHED || true; } | head -c 1073741824 > internal.raw
    before="$(sha256sum < internal.raw)"

    # The prepared stick: exFAT labelled DAWO_LOGS, 48 GiB, sparse, with only
    # the self-test marker (no launch-autostart.txt: a clean boot).
    truncate -s 48G logs.raw
    mkfs.exfat -L DAWO_LOGS logs.raw >/dev/null
    mkdir seed && echo "regression run" > seed/launch-selftest.txt
    python3 ${../../tests/exfat-add-tree.py} logs.raw 0 seed

    cp ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd vars.fd
    chmod u+w vars.fd

    SECONDS=0
    qemu-system-x86_64 \
      -enable-kvm -cpu host -machine q35 -m 12288 -smp 6 \
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
    while [ "$SECONDS" -lt 4200 ]; do
      if grep -a -q "LAUNCH-TEST: DONE ok" serial.log; then result=ok; break; fi
      if grep -a -q "LAUNCH-TEST: DONE fail" serial.log; then result=fail; break; fi
      if ! kill -0 "$(cat qemu.pid)" 2>/dev/null; then result=qemu-exited; break; fi
      sleep 5
    done
    printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"system_powerdown"}' \
      | socat - UNIX-CONNECT:qmp.sock >/dev/null 2>&1 || true
    for _ in $(seq 1 60); do kill -0 "$(cat qemu.pid)" 2>/dev/null || break; sleep 2; done
    kill "$(cat qemu.pid)" 2>/dev/null || true
    sleep 3

    echo "=== DAWO-LIVE / LAUNCH-TEST lines (result: $result after ''${SECONDS}s) ==="
    grep -a "DAWO-LIVE:\|LAUNCH-TEST:" serial.log | tr -d '\r' || true

    after="$(sha256sum < internal.raw)"
    if [ "$before" != "$after" ]; then
      echo "FAIL: the internal disk was modified"
      exit 1
    fi
    echo "internal disk unchanged"

    if [ "$result" != ok ]; then
      echo "FAIL: launch self-test result: $result; last console lines:"
      tail -n 80 serial.log | tr -d '\r' || true
      exit 1
    fi

    mkdir -p $out
    grep -a "DAWO-LIVE:\|LAUNCH-TEST:" serial.log | tr -d '\r' > $out/report.txt
    echo "result=$result seconds=$SECONDS internal-disk=unchanged" >> $out/report.txt
  ''
