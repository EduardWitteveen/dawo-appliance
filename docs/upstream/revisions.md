# Inspected upstream revisions

This file records the exact upstream revisions inspected while designing
`dawo-appliance`. These are the revisions our pins are derived from. Do not
bump them silently; bumping requires re-inspection, and for DAWO-Core a parity
review (`docs/adr/0003-workplace-parity.md`). Ecosystem overview:
`ecosystem.md`.

## DAWO-Core (formerly DAWO-NixOS)

- Repository: <https://codeberg.org/DAWO/DAWO-Core> (primary since release
  0.1.2, 2026-08-14). Backup mirrors:
  <https://code.overheid.nl/MinBZK/DAWO-NixOS>,
  <https://github.com/DAWO-community/DAWO-Core>. Community: <https://dawo.community>.
- **Pinned: tag `0.1.3`, rev `695f17c05ca9fead89774036ddb1d136e77197e4`**
  (2026-09-07). Inspected 2026-09-25. `main` was at `4db976f05c50`
  (2026-09-17, docs/typo commits only after 0.1.3).
- Releases: `v0.1.0` (2026-06-29, "pilot baseline", first tagged release),
  `v0.1.1` (2026-08-05, audit fixes from the first pilot laptops), `v0.1.2`
  (2026-08-14, first release from Codeberg; all inputs updated), `0.1.3`
  (2026-09-07: hardening register, screen lock after 5 minutes, USB control
  opt-in, treefmt/statix/deadnix CI).
- Previously inspected: `daed6f81a189403e41d49df3d76cfb02d1de8ea5` (2026-06-18,
  pre-0.1.0, on code.overheid.nl).
- License: GPL-3.0 (`LICENSE.md`, full GPLv3 text, no SPDX header).
- Flake inputs (from its `flake.lock` at 0.1.3), the ones we align with:
  - `nixpkgs` = `github:nixos/nixpkgs/nixos-26.05` rev
    `fcb8fcd6bf2d0adecae5bd491afaaaf8311b758d` (2026-08-09). **We pin the same
    rev.** (`nixos-25.11`, our previous branch, received its last commit on
    2026-06-30 and is end-of-life.)
  - `nixpkgs-unstable` rev `2fcb964de67f`.
  - `disko` = `github:nix-community/disko/latest` rev
    `de5708739256238fb912c62f03988815db89ec9a` (2026-01-20). **We pin the same
    rev.**
  - Others (not consumed directly by us): flake-parts, import-tree,
    home-manager, nix-maid (Codeberg), kconfig-declarative (Codeberg),
    nixos-hardware, comin, deploy-rs, lanzaboote, rust-overlay, agenix,
    nix-flatpak, treefmt-nix, make-shell. Upstream notes a "sovereignty
    roadmap" to mirror all GitHub-hosted inputs to code.overheid.nl.

Key facts that shape our design (checked at 0.1.3):

- Flake uses `flake-parts` + `import-tree ./modules`. Reusable modules are
  exported as `flake.modules.nixos.<name>` (NOT `nixosModules.*`). Hosts are
  modules named `hosts/<name>` and become `nixosConfigurations.<name>`
  (`modules/flake-parts/host-machines.nix`, which also wires home-manager).
- **The workplace profile is `profiles-dawo-generic`**
  (`modules/hosts/profiles/dawo-generic.nix`). It imports: `hardware-dawo-base`,
  `hardware-displaylink` (opt-in), `boot-tpm2-unlock` (opt-in),
  `profiles-dawo-core` (mandatory hardening, forced on: PAM lockout/quality,
  SSH, sysctl baseline, timesync), `desktop-plasma`, `desktop-gnome`,
  `desktop-sddm-bzk`, `desktop-select`, `environment-*`, `apps-sets`,
  `tools-diagnostics`, `localization-nl_nl`, `networking-client`,
  `nixos-nix-settings`, `nixos-system`, `programs-{git,zsh,chromium,firefox}`,
  `services-{audio,auto-update,update-status,flatpak,printing,scanning}`,
  `users-{basics,dawo,deploy}`. It sets `dawo.autoUpdate.enable = mkDefault true`.
- **Two desktops**: KDE Plasma 6 + SDDM (`dawo.desktop.plasma.enable`) and
  GNOME (`dawo.desktop.gnome.enable`); `desktop-select` asserts exactly one.
- **App sets** (`dawo.apps.*`, off by default except `security` = KeePassXC):
  `office` (LibreOffice or Collabora + Thunderbird), `comms` (Element),
  `creative` (GIMP, Inkscape, Krita, Penpot), `media` (VLC), `dev`.
- **Pilot client host** (`hosts/dawo-t495s`): `boot-loader`,
  `boot-plymouth-bzk`, `disko-single-nvme-luks`, `hardware-lenovo-t495s`,
  `profiles-dawo-generic`, `maid-dawo-generic`; Plasma; apps office + comms +
  creative + media; `dawo.secureboot.enable = false`. This is our parity
  reference (ADR 0003).
- **Hardening register** (`dawo.hardening`): levels baseline / hardened /
  strict, per-rule switches, `dawo-verify` on the device. Mandatory core rules
  are forced; USB control and auditd are opt-in (0.1.3).
- **Auto-update** via comin tracks `https://codeberg.org/DAWO/DAWO-Core.git`
  branch `main` by default and rebuilds the device. We disable it (ADR 0003).
- **Bootstrap user** `users-dawo`: account `dawo` in `wheel`, default password
  documented upstream; `dawo.bootstrapUser.initialHashedPassword` overrides
  it. We supply an install-time generated hash (ADR 0003).
- Disko is still `disko-single-nvme-luks` with the device **hard-coded to
  `/dev/nvme0n1`**; our own explicit-target module stays.
- **Installer hosts now exist**: `hosts/dawo-installer` (headless ISO, wifi +
  SSH key baked in via env, `nixos-anywhere` driven) and
  `hosts/dawo-installer-netboot`. Not used by us (ADR 0002).
- Docs: `architecture.md`, `docs/ROADMAP.md`, `docs/pitfalls.md`,
  `docs/secureboot-tpm.md`, `docs/sovereignty-zero-deps.md`, an mdBook handbook
  under `docs/handbook/`. `CHANGELOG.md` is maintained per release.
- Contribution: Conventional Commits, English for docs/PRs/commits,
  issue-first. CI formats with treefmt, lints with statix + deadnix, produces
  an SBOM.

## mijn-bureau-infra

- Repository: <https://code.overheid.nl/MinBZK/mijn-bureau-infra>
  (mirror: <https://github.com/MinBZK/mijn-bureau-infra>; docs:
  <https://minbzk.github.io/mijn-bureau-infra/>).
- **Pinned: rev `b2ae545013c153b9a3fb0aebcb51d22f348e1573`** (2026-07-27,
  `main` head on the inspection date 2026-09-25; the July commits are
  dependency bumps: Element, LiveKit, Meet, Collabora, Docs). No git tags or
  releases exist.
- Previously inspected: `ef1d796211ad8624ad5a78cb9a828b0926c2933b` (2026-06-16).
- License: EUPL-1.2 (`LICENSE`, `publiccode.yml`).

Key facts that shape our design (checked at `b2ae545`):

- Single-node K3s on Ubuntu 24.04 is **explicitly supported and documented**:
  `docs/docs/getting_started/single-vps-k3s.md` and
  `scripts/single-vps-deploy/` (`01-deploy.sh`, `02-networking.sh`,
  `03-restart-oidc-apps.sh`, `04-nextcloud-office.sh`, `05-docs.sh`,
  `06-grist.sh`, `07-session-lifetimes.sh`, `install.sh`). ClamAV and
  OpenProject are disabled in that setup.
- **K3s is installed unpinned** (`curl -sfL https://get.k3s.io | sh -`) and
  `install.sh` fetches its sub-scripts at run time from a raw URL whose default
  points at a contributor's fork branch (`ritza-co/...`). We must pin K3s
  ourselves (OQ-6) and run the scripts from our pinned revision, never from a
  live URL.
- Deployment tool: Helmfile `1.1.7`; cert-manager `v1.16.2` (ClusterIssuer
  `letsencrypt-prod`, http01 via Traefik). Layout: `helmfile/apps/<app>/
  helmfile-child.yaml.gotmpl`, `helmfile/bases/`, `helmfile/environments/
  {default,demo,production}/`.
- Routing: Traefik ingress is primary; Gateway API controllers are supported
  as an alternative (new since June). HAProxy for OpenShift.
- TLS in the single-VPS path uses **Let's Encrypt** (public domain + email).
  `tls.selfSigned: true` is supported (KIND/local path with mkcert). Base
  domain default `kubernetes.local`.
- **Minimum resources for the single-node deployment: >= 12 vCPU and >= 48 GiB
  RAM** (`prerequisites.md`; tested by upstream on a Hetzner AX41 with 64 GB).
  Sizes `none`/`nano`/`micro`/`small`/...; single-node uses `none`.
- All app secrets are derived from `MIJNBUREAU_MASTER_PASSWORD`. Secrets at
  rest use SOPS + age.
- Image tags are pinned in `helmfile/environments/default/container.yaml.gotmpl`
  (tags, not digests; OQ-5). Notable tags at `b2ae545`: Keycloak
  `26.3.3-debian-12-r0` (bitnamilegacy), Nextcloud `34.0.1-apache`, Collabora
  `26.04.2.2.1`, Synapse `v1.156.0`, Element Web `v1.12.23`, LiveKit
  `v1.13.4`, Meet `v1.23.0`, Docs (impress) `v5.4.1`, Drive `v0.20.0`,
  Conversations `v0.0.19`, Grist `1.7.16`, OpenProject `v16.6.3`, Bureaublad API
  `v0.9.3` / frontend `v0.6.1`, PostgreSQL `17.6.0-debian-12-r4`
  (bitnamilegacy) and CloudNativePG `17.9-standard-bookworm`, Redis
  `8.2.1-debian-12-r0`, MinIO `2025.7.23-debian-12-r5`, Ollama `0.32.1`.
- Shared charts: bitnami PostgreSQL `16.7.18`, Redis `21.2.6`, MinIO `17.0.11`,
  nginx `22.0.0`, Keycloak `24.6.7`, OpenProject `13.8.1`.
- Health: `kubectl get certificate -A` until all Ready (the install script
  waits for a stable count), then per-app smoke checks. The dashboard is
  **`bureaublad`** at `bureaublad.<domain>`, the URL the appliance opens.

## Notes on reuse / licensing

- We do **not** copy upstream source. We consume DAWO-Core as a flake input
  (aggregation) and drive mijn-bureau-infra through its documented Helmfile /
  install scripts at a pinned revision. License interaction (GPL-3.0 vs
  EUPL-1.2) is settled in OQ-4: EUPL-1.2 for this repository.
