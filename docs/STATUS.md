# STATUS — session handoff

Single source of truth for "where were we". Keep it short and current: update
**Now / Next / Recently done** at the end of a work session; `scripts/status.sh`
prints this file plus a few live checks at the start of one. Detail per slice
lives in `roadmap.md`; the verified result of the last real run in
`verification-latest.md`; all documents in `README.md` (this directory).

This is an **experimental, unofficial** appliance, not an official DAWO / Mijn
Bureau / BZK distribution (`AGENTS.md`).

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
- **Environment:** more than one machine now works this repo (see the GitHub
  workflow section below); each has Nix in its own WSL distro (`docs/nix-setup.md`
  has the per-machine table). Repo is LF-only, `core.filemode=false`. Practical
  notes (result links, detached VMs): `development.md`.
- **Slice 4b built (2026-09-25):** per-install appliance CA
  (`hosts/appliance/appliance-ca.nix`, ADR 0004): `dawo-appliance-ca.service`,
  Firefox policy `Certificates.Install`, Chromium NSS import per login,
  `/etc/dawo-appliance/ca.env`; boot-test assertions written
  (`nix/tests/appliance-ca-assertions.py`) but **not yet pasted into
  `test-appliance-boot`** (issue #5). Key on disk = demo, not for production.
- **Slices 4a/5/6/7: code written, offline-tested where a test exists, but
  none of it has been boot-tested or run end-to-end** (see `roadmap.md` for
  exact per-item state; do not trust older summaries, this one supersedes
  them):
  - 4a — guest VM, network, cloud-init (`hosts/appliance/guest-vm.nix`), now
    imported into `hosts/appliance/configuration.nix` so `nix flake check`
    actually evaluates it (it did not before this was noticed and fixed).
    No guest has ever been booted (issue #4's boot-test half is still open).
  - 5 — K3s installer (`k8s/bootstrap/install-k3s.sh`, offline-tested,
    `tests/test-k3s-install.sh`) now wired into the guest's cloud-init; the
    host-side kubeconfig fetch/rewrite half of issue #7 is not done.
  - 6 — Mijn Bureau deploy driver (`apps/mijn-bureau/deploy.sh`) now has an
    offline test (`tests/test-mijnbureau-driver.sh`, 19 assertions); never
    run against a real cluster (issue #8).
  - 7 — health check + dashboard opener, offline-tested
    (`tests/test-health-check.sh`), now wired as XDG autostart
    (`hosts/appliance/appliance-services.nix`); never boot-tested.
  - An internal security review of 4a/5/6 found and fixed 5 real issues
    (credential exposure via `ps`/argv, an SSH host-key check that trusted
    anything, a TOCTOU on a generated disk file, a validation gap that only
    ran on one code path) — see git history, no open issue needed.

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

See the GitHub issue tracker (`github.com/EduardWitteveen/dawo-appliance/issues`)
for the live, per-item backlog — it supersedes any list here. Highlights:
- **Finish Slice 3:** visual review of `nix run .#appliance-vm` (issue #17).
- **Boot-test what's wired:** guest VM (#4), CA assertions (#5), a real K3s +
  Mijn Bureau run (#7, #8), Slice 7 end-to-end (#12) — none of it has run on
  real hardware or a KVM-capable box yet this session.
- Remote is `github.com/EduardWitteveen/dawo-appliance` (public, since
  2026-09-25; OQ-8 partially resolved — release-hosting mechanism still open,
  issue #21).

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

- **OQ-2** — needs a host with >= 16 vCPU / >= 56-64 GiB RAM for the full
  stack end-to-end (Mijn Bureau alone needs >= 12 vCPU / >= 48 GiB in the
  guest); neither machine used so far qualifies.

## Recently done

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
