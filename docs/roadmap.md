# Roadmap

Incremental, vertical slices. Each slice is runnable and adds one layer toward
the full boot-to-demo flow (`docs/architecture.md`). Destructive steps are gated
behind explicit confirmation and built late. Purpose and success criteria:
`docs/purpose.md`.

## Slice 0 — scaffolding (DONE)

- Repository structure, docs, ADRs.
- Pinned manifest format + checksum.
- Minimal Nix flake + dev shell.
- Bootstrap `plan` command (download manifest, verify checksum, print plan,
  **no disk writes**).
- Local tests that need no Nix/root/network.

## Slice 1 — non-destructive live ISO + bootstrap dry-run (DONE 2026-06-22)

A bootable NixOS live ISO that:

- boots successfully ✅ (verified headless in QEMU/KVM);
- has working networking ✅ (NetworkManager);
- contains the `dawo-appliance-bootstrap` command ✅;
- downloads a pinned manifest from a release of this repository ✅
  (`--manifest-url`, incl. `file://`; real release host is OQ-8);
- verifies its checksum ✅;
- shows what would be installed (the plan) ✅;
- **does not write to disk** ✅ (destructive flags refused).

Build: `nix build .#installer-iso` → `dawo-appliance-installer.iso` (1.4 GiB).
Verified two ways: the offline dry-run suite (`nix flake check`, no privileges)
and a full headless boot test (`nix build .#test-installer-boot`, needs KVM)
that boots the live payload and asserts the bootstrap runs non-destructively.

Upstream now ships its own headless fleet installer; we keep ours on purpose
(`docs/adr/0002-own-installer-iso.md`).

## Slice 2 — host install (destructive, gated)

### Slice 2a (DONE 2026-06-22)

- Explicit-target-disk disko module, never a default device
  (`hosts/profiles/disko/single-disk.nix`; sentinel `appliance.targetDisk`).
- Installable host `nixosConfigurations.appliance` (minimal bootable; the
  GRUB-EFI choice of this slice was replaced by upstream's systemd-boot in
  Slice 3).
- Verified: `nix flake check`; the appliance toplevel builds; `diskoScript`
  builds (the layout, touching only the sentinel device); and
  `test-appliance-boot` boots the host config and asserts identity, the operator
  account, the bootstrap and NetworkManager. (`appliance-disk-image` builds a
  full raw image but is KVM-flaky on WSL — see open-questions OQ-9.)

### Slice 2b (DONE 2026-06-22)

- ✅ Bootstrap `install` subcommand: drives `disko-install` on a confirmed
  target disk (`--target-disk` + `--confirm-destroy`, block-device / mount /
  live-medium safety checks, `--dry-run` preview). `disko-install` ships on the
  ISO. Gating covered by the dry-run suite (`docs/testing.md`, R2–R4).
- ✅ Swap subvolume added to the disko layout.
- ❌ LUKS encryption — **out of v0.1 by decision** (experimental demo; basic
  unencrypted storage is enough and simpler to debug). Disk encryption is a
  documented post-MVP hardening option.

### Slice 2c — upstream refresh (DONE 2026-09-25)

Three months of upstream movement, re-inspected and re-pinned
(`docs/upstream/revisions.md`, `manifest/appliance-manifest.json`):

- ✅ DAWO-NixOS became **DAWO-Core on Codeberg**; pinned to release `0.1.3`
  (`695f17c…`). Ecosystem recorded in `docs/upstream/ecosystem.md`.
- ✅ nixpkgs **`nixos-25.11` → `nixos-26.05`** (25.11 is end-of-life), same rev
  DAWO-Core pins; disko to the rev DAWO-Core pins; `stateVersion` 26.05.
- ✅ mijn-bureau-infra pinned to `b2ae545…` (2026-07-27); image tags refreshed.
- ✅ ADR 0002 (keep our own installer), ADR 0003 (workplace parity),
  `docs/purpose.md` (goal, rationale, deviations, trade-offs).
- ✅ Housekeeping: `.gitattributes` (LF-only), environment notes for the
  Windows + WSL setup, stale comments.
- Verification: `nix flake check`, ISO build and both boot tests on 26.05 — see
  `docs/STATUS.md` for the result of this run.

## Slice 3 — DAWO workplace + virtualisation (built 2026-09-25; verification in STATUS.md)

Parity rule: the host **is** the DAWO pilot workplace, plus additions
(`docs/adr/0003-workplace-parity.md`).

- ✅ DAWO-Core `0.1.3` is a pinned flake input (`git+https://codeberg.org/…?ref=refs/tags/0.1.3`,
  rev locked; nixpkgs and disko follow ours, which are upstream's revs).
- ✅ `hosts/appliance/dawo-workplace.nix` imports what a pilot client imports:
  `boot-loader`, `boot-plymouth-bzk`, `profiles-dawo-generic`,
  `maid-dawo-generic`; Plasma; app sets office/comms/creative/media; Secure
  Boot off. Our GRUB and our own `users.users.dawo` are gone (upstream's
  systemd-boot and `users-dawo` apply).
- ✅ Deviations only as listed in ADR 0003: our disko module, generic
  hardware (microcode both vendors), `dawo.autoUpdate.enable = false`,
  **auto-login as `dawo`** plus a **welcome dialog** with the login details
  (demo: nothing to type), upstream's default password by default and an
  install-time generated one with `install --generate-password` (hash shipped
  by `install`, applied once at first boot by
  `dawo-appliance-set-password.service`).
- ✅ KVM/libvirt (`hosts/appliance/virtualisation.nix`): libvirtd + swtpm,
  virt-manager, `dawo` in `libvirtd`.
- ✅ Parity check `checks.workplace-parity` (`nix/parity.nix`) in
  `nix flake check`: 29 user-facing options compared with `hosts/dawo-t495s`
  at the pinned tag; two recorded deviations (auto-update off, auto-login on).
- ✅ `nix run .#appliance-vm`: the host in a QEMU window for a human look.
- ✅ The ISO now ships this flake at `/etc/dawo-appliance/config` (the default
  install source) and `mkpasswd`.
- Boot test `test-appliance-boot` extended: `graphical.target`, SDDM, pilot
  apps present, hardening active, libvirtd, comin inactive, screenshot.

## Slice 4 — Ubuntu 24.04 VM (code written 2026-09-25; not boot-tested)

### Slice 4a — guest VM, network, cloud-init

- ✅ Ubuntu 24.04 cloud image pinned (`release-20260911`, SHA-256) — resolves
  OQ-6 part 1 (`docs/upstream/pins-vm-k3s.md`, manifest `vm.image`).
- ✅ `hosts/appliance/guest-vm.nix`: a dedicated libvirt NAT network
  `dawo-appliance` (fixed DHCP lease, dnsmasq wildcard `*.dawo.internal`, ADR
  0004), a host-side systemd-resolved DNS delegate, a download+checksum
  service for the pinned image, cloud-init rendering
  (`vm/ubuntu-2404/*.in`: user-data, meta-data, network-config, domain.xml)
  and the libvirt domain definition; flagged for autostart. An operator SSH
  key pair is generated on the host once, never in Git.
- ❌ **Not boot-tested.** No automated check starts the guest and asserts
  cloud-init finished or that it answers SSH; `nix flake check` only
  evaluates the Nix module. The guest has never actually been booted on any
  machine so far.
- ❌ The K3s stage inside cloud-init is still an explicit placeholder
  (`vm/ubuntu-2404/user-data.yaml.in`: "NOT IMPLEMENTED YET"). Wiring
  `k8s/bootstrap/install-k3s.sh` (Slice 5) into `runcmd` is unstarted.

### Slice 4b — per-install appliance CA (built 2026-09-25)

- ✅ `hosts/appliance/appliance-ca.nix`: `dawo-appliance-ca.service` generates
  a per-install EC P-256 CA once (never in Git or on the ISO); Firefox trust
  via `Certificates.Install`; Chromium/NSS import per login;
  `/etc/dawo-appliance/ca.env` for scripts.
- ❌ Boot-test assertions are written (`nix/tests/appliance-ca-assertions.py`,
  requirements R20–R22 in `docs/testing.md`) but **not yet pasted into
  `test-appliance-boot`** — the module evaluates and builds as part of the
  appliance host, but nothing has asserted it boots and behaves correctly yet.

## Slice 5 — single-node K3s (installer written and offline-tested 2026-09-25; never run)

- ✅ K3s release pinned (`v1.36.4+k3s1`, binary + `install.sh` SHA-256) —
  resolves OQ-6 part 2 (`docs/upstream/pins-vm-k3s.md`). Upstream installs K3s
  unpinned from `get.k3s.io`; we do not.
- ✅ `k8s/bootstrap/install-k3s.sh`: self-contained, idempotent installer —
  downloads (or takes from `K3S_OFFLINE_DIR`) the pinned `k3s` binary and
  `install.sh`, verifies both by SHA-256, installs with
  `INSTALL_K3S_SKIP_DOWNLOAD` and upstream's exec flags plus `--tls-san`, and
  waits for the node to report Ready.
- ✅ `tests/test-k3s-install.sh`: 13 offline checks (pins equal the manifest,
  tampered binary/`install.sh` rejected, dry run writes nothing, flag
  content) — no network, no root, no Nix required.
- ❌ **Not wired into the guest**: cloud-init still ships the Slice-5
  placeholder (see Slice 4a). The script has never actually run inside a VM;
  no K3s node has ever come up.

## Slice 6 — Mijn Bureau (deploy driver written and offline-tested 2026-09-25; never run)

- ✅ OQ-3 resolved: local DNS + a per-install appliance CA instead of
  self-signed TLS (`docs/adr/0004-local-dns-and-tls.md`).
- ✅ `apps/mijn-bureau/deploy.sh`: a 14-phase driver — obtains
  mijn-bureau-infra at the pinned rev `b2ae545…` (git, hash-verified),
  installs Helm/Helmfile/helm-diff and cert-manager from pinned,
  checksum-verified release artifacts, creates the CA `ClusterIssuer`,
  generates the master password once, runs `helmfile -e demo apply`, drives
  upstream's networking/OIDC-restart/post-fix scripts from the pinned
  checkout, waits for every Certificate to be Ready (stable count), and
  patches in-cluster CA trust into Grist/Docs/Meet/Element. `--dry-run`
  prints every action and changes nothing.
- ⚠️ Partial: in-cluster CA trust for Keycloak (back-channel), Collabora
  (WOPI) and the Docs celery/y-provider and Bureaublad backend runtimes are
  explicit `TODO`s inside `phase_trust`, not yet implemented.
- ❌ Digest-pinning images (OQ-5) is **recorded but not consumed**: 33/34
  images are resolved to a `sha256:` digest in `manifest/image-digests.json`
  (`docs/upstream/image-digests.md`), but this driver still deploys by tag;
  feeding the digests into the Helmfile values is unstarted follow-up work.
- ✅ `tests/test-mijnbureau-driver.sh`: 19 offline checks — full `--dry-run`
  touches no real files/state and calls no real kubectl/curl/git/tar/install/
  sha256sum/python3 (kubectl/curl/etc. are logging fakes on `PATH`, helm/
  helmfile are faked through `MB_BIN_DIR`); `run_phase()` rejects a malformed
  `MB_DOMAIN` before dispatch for all 14 phases, not just `phase_preflight`
  (the gap the 2026-09-25 security fix closed); `phase_password` generates a
  32-char password once and reuses it unchanged; `MB_REV`, `HELMFILE_VERSION`
  and `CERT_MANAGER_VERSION` equal the appliance manifest; `phase_tools` only
  downloads a tool whose detected version does not match the pin;
  `phase_issuer`'s dry-run output matches the ADR 0004 ClusterIssuer/CA-secret
  commands. `HELM_VERSION`, `HELM_DIFF_VERSION` and every `*_SHA256` constant
  have no second recorded copy in this repository, so those are checked for
  well-formedness only.
- ❌ **Never run.** No cluster has ever executed this driver, and Mijn Bureau
  has never been observed deployed or reachable; the offline test above
  covers the driver's own logic, not a real deployment.

## Slice 7 — health + browser (written and offline-tested 2026-09-25; never run against a real deployment)

- ✅ `health/dawo-appliance-health.sh`: nine checks per ADR 0004 (DNS, guest
  reachable, K3s node Ready, `ClusterIssuer` Ready, every Certificate Ready
  with a stable count, every Certificate issued by our issuer, HTTPS 200 on
  the dashboard and on Keycloak's OIDC discovery document with the right
  issuer, Firefox CA trust); `--once`, `--wait --timeout`, `--json`.
- ✅ `health/dawo-appliance-open-dashboard.sh`: waits for health, then opens
  `https://bureaublad.<domain>`; shows a `kdialog` with the failing checks on
  timeout instead of opening a browser that would just error.
- ✅ `tests/test-health-check.sh`: fully offline (fake `ssh`/`curl`/
  `resolvectl`/`ping`/`xdg-open`/`kdialog`), 10 assertions covering the
  all-OK, pending-certificates, issuer-mismatch, DNS-wrong and timeout paths,
  plus the opener in both outcomes.
- ❌ **Not wired into the host**: no NixOS module packages these scripts or
  adds the XDG autostart entry yet (`health/README.md` lists the integration
  work — autostart `.desktop` entry, SSH key readability for the `dawo` user,
  welcome-dialog text, Makefile wiring — as "not done here").
- ❌ Never exercised against a real cluster: since Slices 4–6 have never
  produced a running guest/K3s/Mijn Bureau, this health check has never
  actually observed a real dashboard becoming healthy.

## Hardening (cross-cutting, after MVP)

- Signature verification of manifest + artifacts (OQ-7).
- Reproducibility audit of all pins.
- LUKS (upstream layout), Secure Boot / TPM2 as upstream documents them.
- Offline install (explicitly out of v0.1 scope).

## Decisions needed (see open-questions.md)

- **OQ-2** large host for the full end-to-end run (slices 4–7). — still open;
  this machine cannot run the full stack, so none of Slices 4–7 has been
  exercised end-to-end regardless of code/test state.

Resolved: OQ-1 (WSL `metadata` enabled, git/Nix work here), OQ-3 (local DNS +
TLS, ADR 0004), OQ-4 (license = EUPL-1.2), OQ-6 (K3s + Ubuntu image pins).
OQ-5 (image digests) is resolved as tooling but not yet wired into Slice 6.
Decided 2026-09-25: own installer kept (ADR 0002), workplace parity
(ADR 0003).
