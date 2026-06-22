# Development

> Experimental and unofficial. See `README.md`.

## Prerequisites

- Linux (this repo is developed on Windows + WSL2 / Ubuntu 24.04, x86-64).
- For the no-Nix local checks: `bash`, `coreutils` (`sha256sum`), `curl` or a
  local file path. Optional: `shellcheck`, `jq`.
- For Nix-based checks: a working Nix with flakes enabled. **Not available on
  the current machine** (see OQ-1 in `docs/open-questions.md`).

## Known environment issue (OQ-1)

`/mnt/c` is mounted without `metadata`, so `chmod` fails there and both
`git init` and Nix builds fail on that path. Options and the recommended fix are
in `docs/open-questions.md`. The non-Nix checks below work regardless.

## Local validation (no Nix, no root, no network)

These are runnable right now:

```bash
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

`tests/test-bootstrap-dryrun.sh`:

1. The bootstrap downloads the manifest from a `file://` URL and verifies it
   against the expected SHA-256 — exit 0, plan printed.
2. A **tampered** manifest is rejected (checksum mismatch → non-zero exit).
3. The plan run writes nothing outside its temp dir and never touches a block
   device (no `--target-disk` / `--confirm-destroy` path is exercised).

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

These require Nix with flakes (blocked by OQ-1 on this machine):

```bash
nix flake check          # evaluate flake outputs and run checks
nix develop              # enter the dev shell (git, jq, shellcheck, qemu, …)
nix fmt                  # format Nix files
# ISO build (Slice 1, large; do not run casually):
# nix build .#installer-iso   # (added in Slice 1)
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
| `make test` | Run the local bootstrap test suite (no Nix/root/network). |
| `make plan` | Run the bootstrap dry-run against the local manifest. |
| `make manifest-sum` | Regenerate the manifest checksum file. |
| `make lint` | `shellcheck` the shell scripts. |
| `make fmt` | Format shell scripts with `shfmt` (if installed). |
| `make fmt-check` | Check shell formatting without writing. |
| `make check` | `lint` + `test` (the default local gate). |
