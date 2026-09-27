# Persistent data on the live stick (issue #109): boots the REAL live image
# TWICE with the same 48 GiB exFAT DAWO_LOGS stick (sparse file) and a
# patterned internal disk.
#   boot 1: dawo-data.ext4 is created on the stick, the guest comes up (K3s
#           Ready), the report says "data: stick: created"
#   boot 2: the same file is reused ("data: stick: reused"), the guest comes
#           back with its persisted disk and SSH key, K3s Ready again
# and the internal disk is byte-for-byte unchanged afterwards.
#
# Needs KVM (nested guest). Offline, like test-live-iso-boot.
{ pkgs, iso }:

pkgs.runCommand "live-iso-persist"
{
  requiredSystemFeatures = [ "kvm" ];
  nativeBuildInputs = with pkgs; [ qemu_kvm coreutils gnugrep exfatprogs socat ];
}
  ''
    set -euo pipefail
    isofile="$(echo ${iso}/iso/*.iso)"

    { yes DAWO-INTERNAL-DISK-MUST-STAY-UNTOUCHED || true; } | head -c 1073741824 > internal.raw
    before="$(sha256sum < internal.raw)"

    # The prepared stick: exFAT labelled DAWO_LOGS, 48 GiB, sparse.
    truncate -s 48G logs.raw
    mkfs.exfat -L DAWO_LOGS logs.raw >/dev/null

    cp ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd vars.fd
    chmod u+w vars.fd

    boot() {
      n="$1"
      rm -f "qmp$n.sock" "qemu$n.pid"
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
        -display none -serial "file:serial$n.log" -monitor none \
        -qmp "unix:qmp$n.sock,server=on,wait=off" \
        -pidfile "qemu$n.pid" -daemonize
      SECONDS=0
      result=timeout
      while [ "$SECONDS" -lt 2400 ]; do
        if grep -a -q "DAWO-LIVE: DONE ok" "serial$n.log"; then result=ok; break; fi
        if grep -a -q "DAWO-LIVE: DONE fail" "serial$n.log"; then result=fail; break; fi
        if ! kill -0 "$(cat "qemu$n.pid")" 2>/dev/null; then result=qemu-exited; break; fi
        sleep 5
      done
      echo "=== boot $n: $result after ''${SECONDS}s ==="
      grep -a "DAWO-LIVE:" "serial$n.log" | tr -d '\r' || true
      # Clean shutdown so the data file and the exFAT stick are consistent.
      printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"system_powerdown"}' \
        | socat - "UNIX-CONNECT:qmp$n.sock" >/dev/null 2>&1 || true
      for _ in $(seq 1 90); do kill -0 "$(cat "qemu$n.pid")" 2>/dev/null || break; sleep 2; done
      kill "$(cat "qemu$n.pid")" 2>/dev/null || true
      sleep 2
      if [ "$result" != ok ]; then
        echo "FAIL: boot $n: $result; last console lines:"
        tail -n 60 "serial$n.log" | tr -d '\r' || true
        exit 1
      fi
    }

    boot 1
    grep -a -q "DAWO-LIVE: data: stick: created" serial1.log \
      || { echo "FAIL: boot 1 did not create dawo-data.ext4 on the stick"; exit 1; }
    grep -a -q "DAWO-LIVE: k3s node ready" serial1.log \
      || { echo "FAIL: boot 1: no K3s"; exit 1; }
    # The data setup must be quick: a large preallocated file on exFAT meant
    # ~40 GB of zero-fill on the boot stick (issue #113). The report prints
    # the data line as soon as the setup is done.
    t_data="$(grep -a "DAWO-LIVE: data: stick: created" serial1.log | head -n1 | grep -o 't=[0-9]*s' | tr -dc '0-9')"
    echo "boot 1: data setup finished at t=''${t_data}s"
    if [ -z "$t_data" ] || [ "$t_data" -gt 60 ]; then
      echo "FAIL: boot 1: the data setup took too long (t=''${t_data}s > 60s)"; exit 1
    fi

    boot 2
    grep -a -q "DAWO-LIVE: data: stick: reused" serial2.log \
      || { echo "FAIL: boot 2 did not reuse dawo-data.ext4"; exit 1; }
    grep -a -q "DAWO-LIVE: guest ssh ready" serial2.log \
      || { echo "FAIL: boot 2: the guest did not come back with its persisted key"; exit 1; }
    grep -a -q "DAWO-LIVE: k3s node ready" serial2.log \
      || { echo "FAIL: boot 2: no K3s"; exit 1; }

    fsck.exfat -n logs.raw | tail -n 2

    after="$(sha256sum < internal.raw)"
    [ "$before" = "$after" ] || { echo "FAIL: the internal disk was modified"; exit 1; }
    echo "internal disk unchanged"

    mkdir -p $out
    for n in 1 2; do grep -a "DAWO-LIVE:" "serial$n.log" | tr -d '\r' | sed "s/^/boot $n: /"; done > $out/report.txt
    echo "internal-disk=unchanged" >> $out/report.txt
  ''
