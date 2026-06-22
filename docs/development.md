# Development

> Experimental and unofficial. See `README.md`.

## Prerequisites

- Linux (this repo is developed on Windows + WSL2 / Ubuntu 24.04, x86-64).
- For the no-Nix local checks: `bash`, `coreutils` (`sha256sum`), `curl` or a
  local file path. Optional: `shellcheck`, `jq`.
- For Nix-based checks: a working Nix with flakes enabled. **Nix is not yet
  installed on the current machine** (separate task; `git`/`chmod` now work here
  since OQ-1 was resolved — see `docs/open-questions.md`).

## Environment note (OQ-1 resolved 2026-06-22)

`/mnt/c` now mounts with `metadata`, so `chmod`, `git init`, and commits work on
this path. The repo is initialised on branch `main`. Nix is still not installed
(installing it is a separate task); when it is, keep the Nix store on the WSL
ext4 filesystem rather than the slow `/mnt/c` 9p mount. The non-Nix checks below
work regardless. Full history is in `docs/open-questions.md` (OQ-1).

## Local validation (no Nix, no root, no network)

These are runnable right now:

```bash
# 0. Orient: print where we left off + live checks (run this at session start).
make status
#   equivalent:
bash scripts/status.sh

# 1. Run the full local test (checksum verify + tamper test + no-disk-write).
make test
#   equivalent:
tests/test-bootstrap-dryrun.sh

# 2. Run the bootstrap dry-run ("plan") against the local manifest.
make plan
#   equivalent (offline, reads the manifest from the repo via file://):
#   (invoked via `bash` because /mnt/c cannot set the executable bit — OQ-1)
bash installer/bootstrap/dawo-appliance-bootstrap plan \
    --offline \
    --manifest-url "file://$(pwd)/manifest/appliance-manifest.json"

# 3. Lint shell scripts (needs shellcheck) and check formatting.
make lint
make fmt-check
```

### What the test asserts

`tests/test-bootstrap-dryrun.sh` (4 checks):

1. The committed manifest matches its `.sha256`.
2. The bootstrap downloads the manifest from a `file://` URL and verifies it
   against the expected SHA-256 — exit 0, plan printed, "no disk writes"
   reported.
3. A **tampered** manifest is rejected (checksum mismatch → non-zero exit).
4. Passing `--target-disk` / `--confirm-destroy` is refused (non-zero exit): the
   destructive path is not reachable in v0.1.

### Updating the manifest checksum

The expected checksum is stored in `manifest/appliance-manifest.json.sha256` and
read by the bootstrap. After editing the manifest, regenerate it:

```bash
make manifest-sum     # writes manifest/appliance-manifest.json.sha256
#   equivalent:
( cd manifest && sha256sum appliance-manifest.json > appliance-manifest.json.sha256 )
```

`make test` fails if the manifest and its `.sha256` are out of sync.

## Nix-based checks (when Nix is available)

> Nix is not yet installed here. To install it, follow `docs/nix-setup.md`
> (WSL2 runbook: multi-user install, enable flakes, verify against the flake).

These require Nix with flakes:

```bash
nix flake check          # evaluate flake outputs + portable checks (no kvm)
nix develop              # enter the dev shell (git, jq, shellcheck, qemu, …)
nix fmt                  # format Nix files
nix build .#installer-iso          # build the live ISO (large, ~1.4 GiB)
nix build .#test-installer-boot -L # headless boot test (needs KVM; see nix-setup.md)
```

`flake.lock` is hand-pinned to nixpkgs `nixos-25.11` rev
`d6df3513510aa548c83868fd22bfddd0a8c0a0d4` (the same stable rev DAWO-NixOS
pins). When Nix is available, `nix flake check` will validate it.

## Conventions

- Commit messages: Conventional Commits, English (e.g. `feat(bootstrap): …`).
- Shell: `#!/usr/bin/env bash`, `set -euo pipefail`, must pass `shellcheck`.
- Do not commit unless asked. Do not configure a git remote yet.
- Never commit secrets; never write to a disk without explicit target +
  confirmation.

## Make targets

| Target | Description |
| --- | --- |
| `make status` | Session orientation: where we left off + live checks. |
| `make test` | Run the local bootstrap test suite (no Nix/root/network). |
| `make plan` | Run the bootstrap dry-run against the local manifest. |
| `make manifest-sum` | Regenerate the manifest checksum file. |
| `make lint` | `shellcheck` the shell scripts. |
| `make fmt` | Format shell scripts with `shfmt` (if installed). |
| `make fmt-check` | Check shell formatting without writing. |
| `make check` | `lint` + `test` (the default local gate). |
