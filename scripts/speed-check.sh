#!/usr/bin/env bash
#
# Is this development machine set up for fast builds and fast VM tests?
# Re-entrant: run it any time; it reports each item as OK / FIX and, with
# APPLY=1, applies the fixes it can (some need sudo; it says which). Nothing
# here touches the repository or any disk image.
#
#   bash scripts/speed-check.sh          # report only
#   APPLY=1 bash scripts/speed-check.sh  # apply what is missing (may prompt for sudo)
#
# Why each item matters (measured on the reference laptop, docs/testing.md):
#  - /dev/kvm mode 0666: the Nix sandbox drops the build users' supplementary
#    groups, so group `kvm` on nixbld* is NOT enough; with 0660 every VM test
#    silently falls back to TCG software emulation (accel=kvm:tcg) and takes
#    minutes instead of seconds per boot. This was the cause of the slow runs.
#  - nixbld* in group kvm + `extra-system-features = kvm`: Nix must advertise
#    the feature or tests requiring it are refused / built elsewhere.
#  - WSL2 resources (.wslconfig): by default WSL gets half the RAM and all CPUs;
#    Nix builds + a 6 GiB test VM need memory, nested virtualisation is needed
#    for KVM inside the appliance VM (Slice 4).
set -euo pipefail

ok=0; fix=0
report() { # report STATUS ITEM DETAIL
  case "$1" in
    OK)  ok=$((ok + 1));  printf '  OK   %-34s %s\n' "$2" "$3" ;;
    FIX) fix=$((fix + 1)); printf '  FIX  %-34s %s\n' "$2" "$3" ;;
    *)   printf '  %-4s %-34s %s\n' "$1" "$2" "$3" ;;
  esac
}
apply=${APPLY:-0}

echo "dawo-appliance speed check ($(uname -srm))"

# --- KVM device --------------------------------------------------------------
if [[ -e /dev/kvm ]]; then
  mode="$(stat -c %a /dev/kvm)"
  if [[ "${mode}" == "666" ]]; then
    report OK "/dev/kvm mode" "0666 (Nix sandbox builders can open it)"
  else
    report FIX "/dev/kvm mode" "is 0${mode}; VM tests fall back to slow TCG emulation"
    if [[ "${apply}" -eq 1 ]]; then
      echo "       applying: udev rule + chmod (sudo)"
      sudo bash -c 'printf "KERNEL==\"kvm\", GROUP=\"kvm\", MODE=\"0666\"\n" > /etc/udev/rules.d/99-kvm-nix-sandbox.rules && chmod 666 /dev/kvm && (udevadm control --reload 2>/dev/null || true)'
    fi
  fi
else
  report FIX "/dev/kvm" "missing: no KVM (nested virtualisation off? not WSL2?)"
fi

# --- Nix daemon settings -----------------------------------------------------
if command -v nix >/dev/null 2>&1; then
  feats="$(nix config show 2>/dev/null | sed -n 's/^system-features = //p' || true)"
  if grep -qw kvm <<<"${feats}"; then
    report OK "nix system-features" "kvm advertised"
  else
    report FIX "nix system-features" "kvm missing (add 'extra-system-features = kvm' to /etc/nix/nix.conf, restart nix-daemon)"
    if [[ "${apply}" -eq 1 ]]; then
      echo "       applying (sudo)"
      sudo bash -c 'grep -q "^extra-system-features" /etc/nix/nix.conf || echo "extra-system-features = kvm" >> /etc/nix/nix.conf; systemctl restart nix-daemon 2>/dev/null || true'
    fi
  fi
  if id nixbld1 >/dev/null 2>&1; then
    if id -nG nixbld1 | grep -qw kvm; then
      report OK "nixbld* in group kvm" "yes"
    else
      report FIX "nixbld* in group kvm" "no (harmless with /dev/kvm 0666, needed with 0660)"
      if [[ "${apply}" -eq 1 ]]; then
        sudo bash -c 'for i in $(seq 1 32); do id "nixbld$i" >/dev/null 2>&1 && usermod -aG kvm "nixbld$i"; done'
      fi
    fi
  fi
  # Prove it from inside the sandbox: a derivation that requires the kvm
  # feature and opens /dev/kvm. This is exactly what the VM tests do. Force a
  # fresh run (--rebuild); on the very first run the output does not exist
  # yet and --rebuild refuses, so fall back to a plain (fresh) build then.
  kvm_probe() {
    local out
    if out="$(nix build .#check-kvm --rebuild --no-link --no-warn-dirty 2>&1)"; then return 0; fi
    if grep -q "not valid, so checking is not possible" <<<"${out}"; then
      nix build .#check-kvm --no-link --no-warn-dirty >/dev/null 2>&1; return $?
    fi
    return 1
  }
  if [[ -f flake.nix ]] && kvm_probe; then
    report OK "KVM inside the Nix sandbox" "test VMs use hardware acceleration"
  else
    report FIX "KVM inside the Nix sandbox" "nix build .#check-kvm fails: VM tests run under TCG (slow)"
  fi
else
  report FIX "nix" "not on PATH"
fi

# --- WSL2 resources -------------------------------------------------------------
if grep -qi microsoft /proc/version 2>/dev/null; then
  mem_gib="$(awk '/MemTotal/ { printf "%d", $2/1024/1024 }' /proc/meminfo)"
  cpus="$(nproc)"
  report INFO "WSL2 resources" "${mem_gib} GiB RAM, ${cpus} CPUs visible to WSL"
  winhome="$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')" 2>/dev/null || true)"
  # cmd.exe is not always reachable (PATH, cwd on a Linux path); fall back to
  # the usual mount and pick the profile that has a .wslconfig.
  if [[ -z "${winhome}" || ! -d "${winhome}" ]]; then
    for d in /mnt/c/Users/*/; do [[ -f "${d}.wslconfig" ]] && winhome="${d%/}" && break; done
  fi
  if [[ -n "${winhome}" && -f "${winhome}/.wslconfig" ]]; then
    report OK ".wslconfig" "${winhome}/.wslconfig present ($(grep -E '^(memory|processors|nestedVirtualization)=' "${winhome}/.wslconfig" | tr '\n' ' '))"
  else
    report FIX ".wslconfig" "none: WSL uses half the RAM. Create %USERPROFILE%\\.wslconfig with [wsl2] memory=..., processors=..., nestedVirtualization=true; then 'wsl --shutdown'"
  fi
  if [[ -r /sys/module/kvm_intel/parameters/nested ]]; then
    report INFO "nested virtualisation (guest KVM)" "kvm_intel nested=$(cat /sys/module/kvm_intel/parameters/nested)"
  elif [[ -r /sys/module/kvm_amd/parameters/nested ]]; then
    report INFO "nested virtualisation (guest KVM)" "kvm_amd nested=$(cat /sys/module/kvm_amd/parameters/nested)"
  fi
fi

# --- Nix store location -------------------------------------------------------
if command -v nix >/dev/null 2>&1; then
  fs="$(stat -f -c %T /nix/store 2>/dev/null || echo unknown)"
  if [[ "${fs}" == "9p" || "${fs}" == "v9fs" ]]; then
    report FIX "/nix/store filesystem" "${fs}: on the slow Windows mount; keep the store on WSL ext4"
  else
    report OK "/nix/store filesystem" "${fs}"
  fi
fi

echo
echo "summary: ${ok} OK, ${fix} to fix$([[ "${apply}" -eq 1 ]] && echo ' (APPLY=1 ran; re-run to confirm)')"
[[ "${fix}" -eq 0 ]]
