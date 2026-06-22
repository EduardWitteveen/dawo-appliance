# Inspected upstream revisions

This file records the exact upstream revisions inspected while designing
`dawo-appliance`. These are the revisions our pins are derived from. Do not
bump them silently; bumping requires re-inspection.

## DAWO-NixOS

- Repository: <https://code.overheid.nl/MinBZK/DAWO-NixOS>
- Inspected revision: `daed6f81a189403e41d49df3d76cfb02d1de8ea5`
- Commit date: 2026-06-18
- Default branch: `main`
- License: GPL-3.0 (`LICENSE.md`, full GPLv3 text, no SPDX header)
- nixpkgs pins (from its `flake.lock`):
  - unstable `nixos-unstable` rev `4533d9293756b63904b7238acb84ac8fe4c8c2c4`
  - stable `nixos-25.11` rev `d6df3513510aa548c83868fd22bfddd0a8c0a0d4`
    (narHash `sha256-uJZs9Di8I6ciTp6jiojj0HzlNpBkud8ax5aT/O5aJkw=`)

Key facts that shape our design:

- Flake uses `flake-parts` + `import-tree ./modules`. Reusable modules are
  exported as `flake.modules.nixos.<name>` (NOT the conventional
  `nixosModules.*`). Example names: `desktop-plasma`, `desktop-sddm-bzk`,
  `profiles-dawo-generic`, `disko-single-nvme-luks`, `users-dawo`.
- Desktop is KDE Plasma 6 + SDDM. Enable via the composite
  `profiles-dawo-generic` (imports desktop + locale + networking + hardening).
- Hosts are auto-discovered from modules named `hosts/<name>` and turned into
  `nixosConfigurations.<name>` (e.g. `dawo-t495s`, `dawo-hp-eb-850g7`).
- Disko IS used (`disko-single-nvme-luks`) but the device is **hard-coded to
  `/dev/nvme0n1`** and not parameterised. We need our own explicit-target-disk
  disko module.
- There is **no ISO/installer output** in the flake. Install path is
  `nixos-anywhere` + `deploy-rs` + `comin`. We must build our own live ISO.
- Contribution: Conventional Commits, English for docs/PRs/commits, issue-first.
  No DCO/CLA mentioned.

## mijn-bureau-infra

- Repository: <https://code.overheid.nl/MinBZK/mijn-bureau-infra>
- Inspected revision: `ef1d796211ad8624ad5a78cb9a828b0926c2933b`
- Commit date: 2026-06-16
- Default branch: `main`
- License: EUPL-1.2 (`LICENSE`, `publiccode.yml`)

Key facts that shape our design:

- Single-node K3s on Ubuntu 24.04 is **explicitly supported and documented**:
  `docs/docs/getting_started/single-vps-k3s.md` and
  `scripts/single-vps-deploy/` (idempotent `01-deploy.sh` .. `07-*.sh`).
  One-shot installer:
  `scripts/single-vps-deploy/install.sh DOMAIN you@example.com 'MASTER_PASSWORD'`.
- Deployment tool: Helmfile. Pinned tooling: Helmfile `1.1.7` in the K3s deploy
  script (`1.0.0` in devcontainer), cert-manager `v1.16.2`, KIND/K8s node image
  `v1.34.0`.
- TLS in the documented single-VPS path uses **Let's Encrypt (ClusterIssuer
  `letsencrypt-prod`, http01)** which requires a public domain + email. The
  repo also supports `tls.selfSigned: true` (used in the KIND/local path with
  mkcert). Base domain default is `kubernetes.local`.
- **Minimum resources for the single-node deployment: >= 12 vCPU and >= 48 GiB
  RAM** (`docs/docs/getting_started/prerequisites.md`). Default resource preset
  is `small`; single-node uses preset `none` (no requests/limits).
- Config is supplied via per-environment `*.yaml.gotmpl` files under
  `helmfile/environments/{default,demo,production}/`. All app secrets are
  derived deterministically from a single env var
  `MIJNBUREAU_MASTER_PASSWORD`. Secrets-at-rest use SOPS + age (`.sops.yaml`).
- Image tags are pinned in
  `helmfile/environments/default/container.yaml.gotmpl` (tags, not digests).
- Health checks: `kubectl get certificate -A` (wait until Ready) plus
  documented per-app manual smoke checks (e.g. `https://bureaublad.DOMAIN`).
  Repo tests are Conftest/Rego policies via `scripts/test.sh`,
  `scripts/policy.sh`, and `helmfile template`.
- The dashboard / landing app is **`bureaublad`** at `bureaublad.<domain>` —
  this is the URL the appliance should open in the browser at the end.

## Notes on reuse / licensing

- We do **not** copy upstream source. We consume DAWO-NixOS as a flake input
  (aggregation) and we drive mijn-bureau-infra through its documented Helmfile /
  install scripts, pinned by revision. See `docs/open-questions.md` for the
  GPL-3.0 (DAWO) vs EUPL-1.2 (Mijn Bureau) vs our-license interaction, which is
  an open decision for the repository owner.
