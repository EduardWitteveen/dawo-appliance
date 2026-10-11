# STATUS — session handoff

Single source of truth for "where were we". Keep it short and current: update
**Now / Next / Recently done** at the end of a work session; `scripts/status.sh`
prints this file plus a few live checks at the start of one. Detail per slice
lives in `roadmap.md`; the verified result of the last real run in
`verification-latest.md`; all documents in `README.md` (this directory).

This is an **experimental, unofficial** appliance, not an official DAWO / Mijn
Bureau / BZK distribution (`AGENTS.md`).

## Now

**Handoff 2026-10-11 (Claude session on the KVM laptop, which is also the
Dell Latitude 5550 the live USB is tested on):**

- **Towards v0.1.0** (checklist #175). The live USB works on the Dell: desktop
  ~20 s, guest ~35 s, K3s ~50 s; Mijn Bureau's 14 phases passed on
  2026-09-30. A fresh deploy on 2026-10-11 failed phase 13 because upstream
  installs Nextcloud Office (`richdocuments`) unpinned from the app store and
  only warns when that fails (#205, U5). Fix + Conduction apps: **PR #206**
  (needs-kvm), on the USB SSD now (sha `a107ed7b…`); **a Dell run is the
  next step**, then merge #206.
- **Releases:** the live **disk image** (`.#appliance-live-img`, Rufus/Etcher,
  `DAWO_LOGS` grown on the first boot, #192) is hosted on SourceForge
  (`sourceforge.net/projects/dawo-appliance`, maintainer decision);
  `scripts/release.sh publish` builds and uploads it (#198).
- **Merged 2026-10-10/11:** disk image + ISO mounted from its partition
  (#196, fixes `DAWO_LOGS` staying unused at random), SourceForge release
  path (#198), DAWO-Core v0.2.0 (#199, nixpkgs kept: D40), atomic log files
  (#200), ADR 0008 Launch (#201, #202, #207, #208) and the environment
  catalogue (#204).
- **Next direction (v0.2, ADR 0008):** **Launch**. A clean workplace boots,
  the **Launcher** opens and the user starts an **environment** (*omgeving*:
  Mijn Bureau, Valtimo, Open Zaak, PodiumD, ...) with `launch <id>`; data only
  on the boot disk's `DAWO_LOGS`; a warning before starting when the laptop
  falls short. Nothing in Launch says DAWO: it becomes its own project later.
  Format: `environments/README.md`.

## Next

The live backlog is the GitHub issue tracker; highlights:

1. Dell run with PR #206 on the SSD → merge #206 (#190, #205).
2. v0.1.0-rc.1 (#175): fresh `REPORT=1 E2E=1 bash scripts/verify.sh`, demo
   walk-through with `docs/demo-script.md`, `release.sh prepare/publish`,
   image on SourceForge; then the held-back replies in the DAWO Signal groups.
3. Launch phase B1 (ADR 0008): `launch <id>` / `--stop` / `--status` with the
   preflight warning; the guest starts on demand.
4. `test-live-iso-boot` does not boot the guest under nested KVM in WSL
   (#184), which weakens the KVM merge gate; under investigation.

## GitHub workflow (since 2026-09-25)

More than one Claude session works on this repo, on different machines —
see `AGENTS.md`'s "GitHub workflow" section for the issue/branch/PR/merge
process every change now follows. Known environment difference worth
recording here because it isn't a per-issue concern: **not every machine has
usable KVM.** The original laptop does (`docs/nix-setup.md`); a second
machine used this session is a Nutanix AHV VDI where WSL2 itself reports
"nested virtualization is not supported" — no `.wslconfig` setting fixes
that, it depends on the underlying hypervisor exposing nested-virt to the
Windows guest. `nix flake check` and eval/build-only work still function
fine there; VM boot tests would have to fall back to slow TCG emulation or
run on hardware that actually has KVM.

## Blocking decisions

- What v0.1 means for the installed-to-disk path (#16, #17): ship it as
  experimental, or leave the installer ISO out (ADR 0006 made the live USB
  the default). Maintainer (#175).
- ADR 0008 open points: scope (v0.2), phase D (NixOS microVM guest), when
  Launch moves out, AI-disclosure policy for upstream contributions.

## Verification (historical, 2026-09-25; current: `verification-latest.md`)

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

## Recently done

- 2026-10-06 – 2026-10-11: DAWO community (Signal) feedback → ADR 0008 and
  the Launch design (#193, two research rounds); disk image + SourceForge
  (#192, #196, #198); DAWO-Core v0.2.0 (#195); log files written atomically
  (#197); richdocuments fix and Conduction apps (#205, #206, open).
- 2026-09-27 – 2026-10-03: live USB on real hardware (Dell, Dynabook), Mijn
  Bureau end to end on the Dell (#8), Dutch defaults (#180), visible version
  and release candidates (#175).

- 2026-09-26 (multi-agent orchestration): Formalized `AGENTS.md` and ADR 0005 to manage three concurrent agent sessions. Removed duplicate `CLAUDE.md`. Added `docs/demo-hardware.md` (municipal demo guide). Enforced strict English-only repository content invariant (reverted a Dutch README PR). Added Gemini self-evaluation protocol requiring high-tier reasoning models (`gemini-3.1-pro-high`) to prevent hasty actions. Added rule against autonomous external issue reporting (must be internal GitHub issue first).
- 2026-09-25 (second machine, the Nutanix AHV VDI, no Nix/make/shellcheck/gh
  installed locally at first): committed the session's outstanding work as
  six logical commits (image-digests/OQ-5, Slice 4a guest VM, Slice 7 health
  check, Slice 6 deploy driver, check-upstream, Makefile wiring). Fixed two
  bugs the new machine exposed: `python3` doesn't exist in this Git Bash
  (only `python`) — several scripts now fall back to it; `test-health-check.sh`
  "flip" scenario had a machine-speed-dependent timeout, now a generous
  bound instead of the assertion. Installed `gh` and later `shellcheck`
  (checksum-verified release downloads, no winget here), created the public
  GitHub repo, pushed `main`; then installed Nix (2.34.7, pinned) here too —
  `nix flake check` passes on this machine as well (all checks; VM boot
  tests cannot run here, no KVM — see the GitHub workflow note above).
  Adopted the multi-session GitHub workflow (issues/branches/PRs) mid-session
  after discovering another Claude session had already set it up concurrently
  on the same repo (24 issues, PR #2 merged) — re-authored this session's
  not-yet-pushed local commits to the shared identity before opening PRs.
- 2026-09-25 Slice 3 + Slice 2c (see Now); `install --generate-password`,
  welcome dialog, `appliance-vm`, parity check, `verify.sh` + report,
  `speed-check.sh`, `screenshots.sh`, docs tidy (index, front-door README).
- 2026-06-22 Slices 0–2: manifest + checksum, flake/dev shell, bootstrap, ISO,
  boot tests, disko layout, gated `install`, swap; LUKS deferred.
