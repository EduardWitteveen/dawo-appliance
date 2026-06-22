# STATUS — session handoff

Single source of truth for "where were we". Keep this short and current.
Update the **Now / Next / Recently done** sections at the end of a work session;
`scripts/status.sh` prints this file plus a few live checks at the start of one.

This is an **experimental, unofficial** appliance — not an official DAWO / Mijn
Bureau / BZK distribution (see `CLAUDE.md`).

## Now

- **Slice 1** (current target): non-destructive live ISO + bootstrap dry-run.
- The bootstrap `plan` / `verify` commands work and are covered by the offline
  dry-run test suite (`tests/test-bootstrap-dryrun.sh`).
- Slices 2–7 are scaffolding (README placeholders) only.

## Next

- **`git init` the repo** — now unblocked (OQ-1 resolved). Commits need
  maintainer approval; no remote yet.
- Install Nix (separate task), then build/boot the live ISO
  (`installer/iso/iso.nix`). Prefer the Nix store on the WSL ext4 filesystem,
  not the `/mnt/c` 9p mount.
- Resolve OQ-3 (local DNS + self-signed TLS) before slices 6–7 can start.

## Blocking decisions

- **OQ-1** — RESOLVED 2026-06-22. `/mnt/c` now mounts with `metadata`;
  `chmod` / `git init` work here. See `docs/open-questions.md`.
- **OQ-3** — local DNS/TLS strategy; blocks Mijn Bureau + browser slices.
- **OQ-2** — this machine has 15 GiB RAM; cannot run the full stack end-to-end.

## Recently done

- Pinned manifest + checksum, minimal flake/dev shell, bootstrap `plan`/`verify`.
- Offline dry-run test suite (4 checks, all passing).
- This handoff doc + `scripts/status.sh` orientation helper.
- OQ-1 resolved: WSL `metadata` enabled, `git init` verified working on `/mnt/c`.

## Quick pointers

- Roadmap (all slices): `docs/roadmap.md`
- Open questions / decisions: `docs/open-questions.md`
- Architecture: `docs/architecture.md`
- Local dev commands: `docs/development.md`, `Makefile`
