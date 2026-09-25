# STATUS — session handoff

Single source of truth for "where were we". Keep it short and current: update
**Now / Next / Recently done** at the end of a work session; `scripts/status.sh`
prints this file plus a few live checks at the start of one. Detail per slice
lives in `roadmap.md`; the verified result of the last real run in
`verification-latest.md`; all documents in `README.md` (this directory).

This is an **experimental, unofficial** appliance, not an official DAWO / Mijn
Bureau / BZK distribution (`CLAUDE.md`).

## Now

- **Slices 0–2 done and verified** (2026-06-22): live ISO, non-destructive
  bootstrap (`plan`/`verify`), gated `install` (disko, explicit `--target-disk`
  + `--confirm-destroy`, `--dry-run`), Btrfs + swap, no LUKS.
- **Slice 2c done** (2026-09-25): upstream refresh to DAWO-Core 0.1.3
  (Codeberg), nixpkgs 26.05, mijn-bureau-infra `b2ae545…`; ADR 0002/0003,
  `purpose.md`, `upstream/ecosystem.md`.
- **Slice 3 built and boot-tested** (2026-09-25): the host is the DAWO
  workplace (`hosts/appliance/dawo-workplace.nix`, same modules and choices as
  a pilot client) plus KVM/libvirt, a first-boot password service and a welcome
  dialog. Recorded deviations (ADR 0003): auto-update off, auto-login on.
  Parity check `checks.workplace-parity` in `nix flake check`;
  `nix run .#appliance-vm` for a human look. Visual review still pending.
- **Docs tidied** (2026-09-25): one index (`docs/README.md`), README as front
  door with the two screenshots, overlap removed between `development.md`,
  `nix-setup.md` and `testing.md`; stale statements fixed.
- **Environment:** the session runs on the Windows side; Nix lives in WSL
  `Ubuntu-24.04` (`wsl -d Ubuntu-24.04 -e bash -lc '… nix …'`); WSL has 24 GB /
  12 CPUs via `.wslconfig`. Repo is LF-only, `core.filemode=false`. Practical
  notes (result links, detached VMs): `development.md`.
- Slices 4–7 are scaffolding (README placeholders) only.

## Verification (2026-09-25, nixos-26.05, DAWO-Core 0.1.3)

`bash scripts/verify.sh`: **all executed checks passed** (7 PASS, 1 SKIP:
`shellcheck-local`, no shellcheck in WSL, covered by `nix flake check`). The
only source of truth is `verification-latest.md` (written by
`REPORT=1 bash scripts/verify.sh`), with per-check durations and the boot
timing of the installed host. Screenshots in `screenshots/` come from the same
tests (`scripts/screenshots.sh`). Local dry-run suite: 10 checks (the stage
tree check needs the whois `mkpasswd`; it is skipped in Git Bash and runs in
`nix flake check`).

Bugs found and turned into checks today (`testing.md`):
- **All VM tests had run under TCG emulation** (Nix sandbox drops supplementary
  groups, so `/dev/kvm` 0660 is unusable). Fixed via udev rule 0666 +
  `.wslconfig`; new `scripts/speed-check.sh` and the `kvm-in-sandbox` check.
- The installer test did not see the flake copy / `disko-install` (ISO-only)
  → shared `liveInstallerExtras` module for ISO and test.
- `pgrep -x plasmashell` never matches NixOS's wrapped binary → `pgrep -f`.
- `clear` without TERM, SDDM config not in `/etc` → behaviour-based asserts.
- `--rebuild` refuses never-built derivations → `fresh_build` helper.
- One unexplained guest freeze at 55 s in a TCG run (TSC unstable); not seen
  again under KVM. Watch for it.
- Review agent (2026-09-25) found four real install-path bugs, all fixed with
  checks: `cp -ar STAGE/. /` would have made `/` 0700 (now `STAGE/var` ->
  `/var`, suite check 9); `grep -c` + pipefail aborted on unmounted disks
  (installer test on a spare `/dev/vdb`); `/etc/dawo-appliance/config` is a
  symlink Nix refuses as a flake (resolved with `readlink -f`, asserted);
  UEFI + live-store space are checked before erasing, `--write-efi-boot-entries`
  added, stage cleaned by trap.
- One `mksquashfs` segfault during an ISO build while a 6 GiB VM was running;
  the retry passed. Watch for it under memory pressure.

## Next

- **Finish Slice 3:** look at the desktop in `nix run .#appliance-vm` and fix
  anything visibly off (welcome dialog wording, panel layout from nix-maid);
  then mark Slice 3 done in `README.md` and `roadmap.md`.
- **Slice 4 — Ubuntu 24.04 VM:** pin the cloud image (version + SHA-256,
  OQ-6), libvirt domain + cloud-init, autostart. Nested KVM works inside
  `appliance-vm` (guest kernel reports "kvm_amd: Nested Virtualization enabled").
- Resolve OQ-3 (local DNS + self-signed TLS) before slices 6–7 can start.
- No remote yet (OQ-8). Commits need maintainer approval: **all of today's work
  (Slice 2c, Slice 3, docs tidy) is uncommitted; it is staged with `git add`
  so the flake sees it.**

## Blocking decisions

- **OQ-3** — local DNS/TLS strategy; blocks Mijn Bureau + browser slices.
- **OQ-2** — this machine (24 GB for WSL) cannot run the full stack end-to-end.

## Recently done

- 2026-09-25 Slice 3 + Slice 2c (see Now); `install --generate-password`,
  welcome dialog, `appliance-vm`, parity check, `verify.sh` + report,
  `speed-check.sh`, `screenshots.sh`, docs tidy (index, front-door README).
- 2026-06-22 Slices 0–2: manifest + checksum, flake/dev shell, bootstrap, ISO,
  boot tests, disko layout, gated `install`, swap; LUKS deferred.
