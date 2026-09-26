# Development

> Experimental and unofficial. See `README.md`. Rules and working method:
> `AGENTS.md`. What each check covers: `testing.md`.

## Prerequisites

- Linux with `bash` and `coreutils` for the local checks; optional `shellcheck`,
  `shfmt`, `jq`.
- Nix with flakes for everything else. On the Windows + WSL2 development
  machine Nix lives only in the WSL distro `Ubuntu-24.04`; run it from Windows
  as `wsl -d Ubuntu-24.04 -e bash -lc 'cd /mnt/c/git/dawo-appliance && nix flake check'`.
  Installing Nix and making KVM usable: `nix-setup.md`.
- The repository is LF-only (`.gitattributes`); Windows git uses
  `core.autocrlf=true` and `core.filemode=false` locally. Scripts are invoked
  via `bash …` so the executable bit does not matter.

## Session start

```bash
make status          # or: bash scripts/status.sh
```

Prints where we left off (`STATUS.md`), the blocking open questions, live checks
(manifest checksum, dry-run suite) and recently changed files. No Nix, network
or git needed.

## Local checks (no Nix, no root, no network)

```bash
make check           # lint (shellcheck, if installed) + test; the default local gate
make test            # tests/test-bootstrap-dryrun.sh
make plan            # bootstrap dry-run against the local manifest (file:// URL)
make verify-manifest # bootstrap `verify` only: manifest checksum
make fmt-check       # shfmt diff (if installed); `make fmt` writes
```

`tests/test-bootstrap-dryrun.sh` runs nine checks: the committed manifest
matches its `.sha256`; `plan` verifies a `file://` manifest and reports no disk
writes; a tampered manifest is rejected; `plan`/`verify` refuse
`--target-disk` and `--confirm-destroy`; `install` refuses a missing target, a
non-block device and a missing `--confirm-destroy`; `install --dry-run` (with
and without `--generate-password`) previews and writes nothing. The same suite
runs sandboxed in `nix flake check` (`checks.bootstrap-dryrun`).

### After editing the manifest

```bash
make manifest-sum    # rewrites manifest/appliance-manifest.json.sha256
```

`make test` fails while the manifest and its `.sha256` disagree. Every pin
bump also updates `upstream/revisions.md` and, for DAWO-Core, needs a parity
review (`adr/0003-workplace-parity.md`).

## Nix checks and builds

```bash
nix flake check                    # eval + bootstrap-dryrun + shellcheck + workplace-parity (no KVM)
nix develop                        # dev shell: git, jq, shellcheck, shfmt, gnumake, qemu, nixpkgs-fmt
nix fmt                            # format Nix files
nix build .#installer-iso          # the live ISO (~1.4 GiB) at result/iso/
nix build .#test-installer-boot -L # boots the ISO payload headless, asserts the bootstrap is non-destructive (KVM)
nix build .#test-appliance-boot -L # boots the installed host: DAWO workplace, libvirt, hardening, welcome dialog (KVM)
nix build .#appliance-vm           # the run script for the VM below
nix run   .#appliance-vm           # the installed host in a QEMU window (KVM + display)
nix build .#appliance-disk-image   # raw disk image via disko; KVM-flaky on WSL (OQ-9)
```

`checks.workplace-parity` (`nix/parity.nix`) compares the user-facing option
values of our host with upstream's pilot host `hosts/dawo-t495s` at the pinned
DAWO-Core tag and fails with a report when they drift (ADR 0003).

### The full suite in one command

```bash
bash scripts/verify.sh            # everything above, one summary table
QUICK=1 bash scripts/verify.sh    # dry-run suite + nix flake check only
FORCE=1 bash scripts/verify.sh    # re-run boot tests even when Nix cached a pass
REPORT=1 bash scripts/verify.sh   # also write verification-latest.md (+ history.csv)
```

Run `bash scripts/speed-check.sh` first (`APPLY=1` to fix with sudo): it
checks that `/dev/kvm` is usable inside the Nix sandbox, the WSL2 resources and
the Nix store location. Without it the VM tests run under software emulation
and take minutes per boot (`testing.md`).

### Looking at the workplace: `nix run .#appliance-vm`

Boots `nixosConfigurations.appliance-vm` (the appliance host plus
`hosts/appliance/vm.nix`) in QEMU with a window. Needs KVM and about 6 GiB RAM
for the guest; inside WSL, WSLg shows the window on the Windows desktop. The VM
auto-logs in as `dawo`; the screen lock accepts upstream's documented bootstrap
default password (a VM run has no install-time password; see
`hosts/appliance/appliance-services.nix`). The first start downloads the Plasma
closure; later starts are fast. The VM disk `dawo-appliance.qcow2` is written to
the current directory (git-ignored), so start it from a directory on ext4, not
on `/mnt/c`. WSL cleans `/tmp` between sessions: put `nix build -o` result
links in the home directory. A detached VM survives only when started from a
Windows process (`Start-Process wsl …`), not via `nohup`/`setsid` inside a
`wsl -e` call.

### Bumping nixpkgs or disko

`flake.lock` pins the same nixpkgs and disko revisions DAWO-Core pins
(`upstream/revisions.md`, `manifest/appliance-manifest.json`). Bump explicitly
so the lock never drifts from the manifest:

```bash
nix flake lock --override-input nixpkgs github:NixOS/nixpkgs/<rev>
```

## Refreshing the screenshots

```bash
make screenshots     # bash scripts/screenshots.sh (Linux + Nix + KVM)
```

Copies the PNGs from the boot tests into `screenshots/` and rewrites
`screenshots/PROVENANCE.md`. Do this after `verify.sh` is green and before
updating the README (`screenshots/README.md`).

## Make targets

| Target | Description |
| --- | --- |
| `make status` | Session orientation: where we left off + live checks. |
| `make check` | `lint` + `test` (default). |
| `make test` | Local dry-run test suite. |
| `make plan` | Bootstrap `plan` against the local manifest. |
| `make verify-manifest` | Bootstrap `verify` against the local manifest. |
| `make manifest-sum` | Regenerate the manifest checksum file. |
| `make lint` / `make fmt` / `make fmt-check` | `shellcheck` / `shfmt -w` / `shfmt -d` on the shell scripts. |
| `make verify` | Full verification suite (`scripts/verify.sh`; Linux + Nix + KVM). |
| `make speed-check` | Is this machine set up for fast builds and VM tests? |
| `make screenshots` | Refresh `docs/screenshots/` from the boot tests. |
