# ADR 0007: A laptop profile for Mijn Bureau

- Status: Accepted (2026-09-28, maintainer: "Mijn Bureau in the browser from the live stick" on a 32 GB laptop)
- Date: 2026-09-28
- Deciders: maintainer (eywitteveen)
- Refs: #110, #11 (sizing research), ADR 0006 (live USB)

## Context

Upstream's single-VPS path (mijn-bureau-infra `b2ae545`,
`scripts/single-vps-deploy/`) deploys nine apps with `resourcesPreset:
"none"` and recommends 12 vCPU / 48 GiB. The machines the live USB runs on
are laptops: the reference Dell Latitude 5550 has 12 threads and 32 GB, of
which the desktop keeps 6 GB (`appliance.guest.fitToHost`). The sizing
research (`docs/upstream/mijn-bureau-sizing.md`) computed, with upstream's own
`predicted_resources.py`, a **laptop-demo** profile: Keycloak, Bureaublad,
Nextcloud, Collabora and Element/Synapse on the `micro` preset with
upstream's per-app map — about 6 CPU / 7.3 GiB in requests and 9.9 CPU /
11.3 GiB in limits.

## Decision

1. `apps/mijn-bureau/deploy.sh` gets `MB_PROFILE`:
   - `full` (default): upstream's set and preset, unchanged.
   - `laptop-demo`: the five core apps; Grist, Docs, Meet and LiveKit are
     `enabled: false`; `global.resourcesPreset: "micro"` without a
     `resourcesPresetPerApp` override.
2. The live USB deploys `laptop-demo`; its guest may use up to 16 GiB and
   8 vCPUs (still capped by `fitToHost`).
3. Upstream's post-deploy scripts stay the source: `02-networking.sh` runs
   as is (the namespaces of the left-out apps are created empty so its
   per-namespace loop works; its final LiveKit step may fail, which the
   driver checks is the only failure); `05-docs.sh` and `06-grist.sh` are
   skipped; of `03-restart-oidc-apps.sh` only the Nextcloud and Synapse
   steps run, because the script restarts the left-out apps under
   `set -e` (deviation D29).

## Consequences

- A laptop demo shows the Mijn Bureau dashboard, files and office editing,
  single sign-on and chat, but not Docs, Grist or video calls.
- Parity with upstream is kept for everything that is deployed; the
  differences are the app selection and the resource preset, both upstream
  knobs.
- `laptop-demo-plus` (Docs, Grist, Meet on the `nano` preset, ~22 GiB guest)
  stays a possible later profile; it is not built now.
