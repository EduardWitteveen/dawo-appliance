# Testing: what is checked, by which test

> Experimental and unofficial. See `README.md`.

One command runs everything we have and prints a table:

```bash
bash scripts/verify.sh          # full suite (Linux, Nix, KVM; on this machine inside WSL Ubuntu-24.04)
QUICK=1 bash scripts/verify.sh  # fast checks only (no builds, no VMs)
FORCE=1 bash scripts/verify.sh  # re-run boot tests even if Nix cached a pass
```

`make check` (lint + local dry-run) needs no Nix. `nix flake check` runs the
sandboxed checks (dry-run suite, shellcheck, workplace parity). The boot tests
and image builds are separate `nix build` targets because they need KVM or are
large; `scripts/verify.sh` (`make verify`) chains all of them. Day-to-day
commands: `development.md`.

## The rule: a bug becomes a check first

Test-driven, in the small: when something goes wrong (a failing boot, a wrong
assumption about upstream, a flaky assertion), the fix ships together with a
check that would have caught it, and the check stays in the suite and in the
matrix below. `docs/verification-latest.md` is written **only** by
`REPORT=1 bash scripts/verify.sh`, so the status the README points to always
comes from a real run. Examples from 2026-09-25: the process-name match for
wrapped binaries (`pgrep -f`), the 600 s budget for a software-rendered Plasma
start, the read-only-nixpkgs and `consoleLogLevel` conflicts in the test node
(caught by `nix flake check`), the first-boot password service unit test.

## Is the machine set up for speed?

`bash scripts/speed-check.sh` (re-entrant; `APPLY=1` fixes what needs sudo)
checks the things that decide between minutes and seconds: `/dev/kvm` mode
0666 (the Nix sandbox drops supplementary groups, so group `kvm` on `nixbld*`
is not enough), the `kvm` system feature, a real KVM probe from inside the
sandbox (`nix build .#check-kvm`), WSL2 resources (`.wslconfig`), nested
virtualisation and the Nix store filesystem. `verify.sh` runs the sandbox KVM
probe as its own check so a regression is visible in the report. Found on
2026-09-25: every VM test so far had run under TCG emulation.

## How long things take

`REPORT=1 bash scripts/verify.sh` appends every check's duration to
`docs/verification-history.csv` and shows mean, range and sample count per
check in `docs/verification-latest.md`. The appliance boot test also writes
`timing.txt` (seconds from power-on to `multi-user.target`,
`graphical.target`, the Plasma session and the welcome dialog) into its result;
the report shows it as "Boot timing". Read the numbers with the cache in mind:
the first run downloads several GB, later runs reuse the Nix store, and a
cached passing test returns in seconds unless `FORCE=1`. Boot timings come
from a software-rendered 4-vCPU test VM and are worst-case; real hardware with
GPU acceleration is much faster.

## Requirement → test matrix

| # | Requirement (from `docs/purpose.md`, ADRs, `AGENTS.md`) | Where it is checked | How |
| --- | --- | --- | --- |
| R1 | Manifest is the pinned root of trust; tampering is detected | `tests/test-bootstrap-dryrun.sh` 1–3; `nix flake check` (`bootstrap-dryrun`) | committed `.sha256` matches; `plan` verifies and prints the plan; a tampered manifest is rejected |
| R2 | Non-destructive by default: `plan`/`verify` never write; destructive flags refused | dry-run suite 4; `test-installer-boot` | `--target-disk`/`--confirm-destroy` on `plan` exit non-zero |
| R3 | `install` needs an explicit target disk AND `--confirm-destroy`; refuses non-block devices, mounted disks and the running system's disk; UEFI and live-store space are checked before erasing | dry-run suite 5, 6, 8; `test-installer-boot` | refusals without target, with a non-device, without confirmation; on the ISO a spare unmounted disk (`/dev/vdb`) is refused *because of* the missing `--confirm-destroy` and stays untouched, the live disk is refused outright |
| R3b | The generated-password files are copied into the fresh root without changing the mode of `/` | dry-run suite 9 (`stage-password-files` + `cp -ar STAGE/var ROOT/var`) | root stays 0755; hash 0600; plain text 0644 |
| R3c | The default install source `/etc/dawo-appliance/config` (a symlink into the store) is resolved to a path Nix accepts as a flake | `test-installer-boot` | dry-run output shows `flake: /nix/store/...` |
| R4 | `install --dry-run` previews (incl. the password step) and writes nothing | dry-run suite 7, 7b; `test-installer-boot` | output markers `INSTALL PLAN`, `NO DISK WRITES PERFORMED`, `disko-install --flake`, `extra-files` |
| R5 | Shell code is `set -euo pipefail` and shellcheck-clean | `nix flake check` (`shellcheck`) | bootstrap, dry-run suite, `status.sh`, `verify.sh` |
| R6 | The live ISO builds, boots, has networking, ships the bootstrap, manifest, checksum, this flake and disko-install | `nix build .#installer-iso`; `test-installer-boot` | ISO named `dawo-appliance-installer.iso`; boot to `multi-user.target`; files under `/etc/dawo-appliance/`; `command -v disko-install` |
| R7 | The installed host evaluates and builds on the pinned nixpkgs; storage layout applies only to an explicit device | `nix flake check` (evaluates `nixosConfigurations.appliance`); `nix build .#appliance-disk-image` (KVM-flaky on WSL, OQ-9) | sentinel default device; `diskoScript` builds |
| R8 | **Workplace parity**: the host makes the same user-facing choices as upstream's pilot host at the pinned DAWO-Core tag; only recorded deviations differ | `nix flake check` (`workplace-parity`, `nix/parity.nix`) | 29 options compared with `hosts/dawo-t495s`; recorded deviations must hold on both sides; anything else that differs fails with a report |
| R9 | The host boots to the DAWO workplace: SDDM + Plasma reach `graphical.target`; the pilot app set is installed | `test-appliance-boot` | units; `command -v` for libreoffice, thunderbird, element-desktop, gimp, inkscape, krita, vlc, keepassxc, firefox, plasmashell |
| R10 | Upstream's mandatory hardening is active on the appliance | `test-appliance-boot` | `kptr_restrict != 0` (sysctl baseline); sshd enabled with `PasswordAuthentication no` |
| R11 | Auto-update (comin) is off on the appliance (ADR 0003) | `test-appliance-boot`; `workplace-parity` | `comin.service` inactive; recorded deviation `dawo.autoUpdate.enable` |
| R12 | KVM/libvirt present; `dawo` is a wheel admin and may manage VMs | `test-appliance-boot` | `libvirtd.service` active; `virsh list`; group membership |
| R13 | Demo ergonomics: auto-login as `dawo`, Plasma session starts, welcome dialog appears | `test-appliance-boot`; `workplace-parity` | SDDM is the display manager; a `dawo` login session and `plasmashell`/`kdialog` appear without input; autostart entry present; recorded deviation `autoLogin.enable` |
| R14 | Install-time generated password is applied once at first boot; hash file removed; plain text stays readable for the welcome dialog (`install --generate-password`, demo only) | `test-appliance-boot` | drop a hash + plain text, start `dawo-appliance-set-password.service`, compare `getent shadow dawo`, check hash gone and `dawo` can read `dawo.password.txt` |
| R15 | The host runs as a local VM for a human look | `nix build .#appliance-vm` (in `verify.sh`) | builds `run-dawo-appliance-vm`; the look itself is manual |
| R16 | No secrets in Git | review + `.gitignore` patterns | manual; the only password in the tree is upstream's documented default |
| R17 | Pins are exact and recorded | `manifest/appliance-manifest.json`, `flake.lock`, `docs/upstream/revisions.md` | manual review on every bump; `nix flake check` fails if the lock and flake disagree |
| R23 | **A real install works end to end**: the live installer (UEFI) runs `dawo-appliance-bootstrap install --target-disk ... --confirm-destroy --generate-password` on an empty disk; the disk then boots by itself (systemd-boot) into the DAWO workplace | `test-install-e2e` (opt-in in `verify.sh`: `E2E=1`) | install reports success; target: UEFI, `bootctl is-installed`, hostname, Btrfs root, `/` mode 755, password hash applied and plain text kept, `dawo` Plasma session, CA service; prints install/boot/desktop timings (2026-09-25: 1657 s / +24 s / +27 s) |
| R24 | **Guest VM wired (Slice 4a):** the libvirt network `dawo-appliance` is active; the host resolves `*.dawo.internal` to 192.168.150.10 via a systemd-resolved DNS delegate; the guest overlay disk, the cloud-init seed (host-generated SSH key, appliance CA) and the domain `dawo-appliance-mb` exist | `test-appliance-boot` (guest defined, not started: no nested guest boot in the test; local empty image instead of the pinned download) | `virsh net-info`, `resolvectl query bureaublad./id.dawo.internal`, `virsh dominfo`, seed and key files, `ssh-ed25519` and `BEGIN CERTIFICATE` in user-data |
| R20 | **Per-install appliance CA** (ADR 0004): generated once at first boot, before the display manager; `ca.crt` 0644 with `CA:TRUE` + keyCertSign/cRLSign, `ca.key` 0600 root and unreadable for `dawo`, `ca.crt.sha256` valid; a restart does not regenerate; `/etc/dawo-appliance/ca.env` names the files. The key on disk is a demo choice, not for production | `test-appliance-boot` (assertions in `nix/tests/appliance-ca-assertions.py`, block A) | unit active (RemainAfterExit); `stat`, `openssl x509 -text`, `sha256sum -c`, fingerprint equal before/after restart |
| R21 | Firefox trusts the CA through the enterprise policy `Certificates.Install`, merged with upstream's policies (no override) | `test-appliance-boot` (block A); `nix flake check` evaluates the merged attrset | `/etc/firefox/policies/policies.json` contains the CA path and upstream's `DisableTelemetry`/Plasma integration entries |
| R22 | Chromium trusts the CA: the per-login user service imports it into `~/.pki/nssdb` of the logged-in `dawo` user, idempotently | `test-appliance-boot` (block B, after the Plasma session) | `dawo-appliance-ca-nss.service` active in the user manager; `certutil -L` lists exactly one `DAWO appliance local CA` with trust `C,,`, DER equal to `ca.crt`; a restart keeps one entry |
| R26 | **The Ubuntu guest really boots** (nested KVM): pinned cloud image (fetched by its manifest SHA-256), fixed lease 192.168.150.10, SSH with the host-generated key, hostname `mb.dawo.internal`, cloud-init finished with only the two offline-caused module failures (apt `qemu-guest-agent`, K3s `runcmd`), appliance CA in the guest trust store | `test-guest-boot` (needs nested KVM; ~5 min; 2026-09-26: SSH at 168 s, cloud-init at 287 s) | domain running, DHCP lease, `ssh ops@… hostname -f`, `cloud-init status --format json`, CA line in `/etc/ssl/certs/ca-certificates.crt`, `dawo-appliance-guest-status` |

## Not (yet) automated

- A real install on **hardware** (#16). The same install path runs in a VM in
  `test-install-e2e` (R23), including the UEFI boot from the written disk.
- The visual result (panel layout, wallpaper, dialog wording): look at
  `nix run .#appliance-vm`. The boot test's `desktop.png` screenshot is best
  effort in a software-rendered VM.
- Slice 4a (guest VM) has no offline test of its own yet. Slice 4b's CA
  assertions (R20–R22) run in `test-appliance-boot`. Slices 5–7 (K3s, Mijn
  Bureau, health) each have an offline test
  (`tests/test-k3s-install.sh`, `tests/test-mijnbureau-driver.sh`,
  `tests/test-health-check.sh`), but none of the five has ever run against a
  real guest, cluster or deployment — only their offline, fully-faked logic is
  covered. Guest and cluster trust in the CA are Slice 4a/6 tests. The
  end-to-end run also needs a large host (OQ-2).

## Reading a failure

- Dry-run suite: prints `FAIL <check>` with the captured output.
- `workplace-parity`: the evaluation error lists every compared option as
  `same`, `MISMATCH`, `DEVIATION (recorded)` or `DEVIATION DRIFTED`.
- Boot tests: the `!!!` lines name the failed assertion; the serial console
  log precedes it. Plasma in a software-rendered VM takes minutes; process
  names are matched with `pgrep -f` because NixOS wraps binaries
  (`.plasmashell-wrapped`).
