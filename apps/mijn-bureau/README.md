# Mijn Bureau deployment (Slice 6, not implemented yet)

Drives the upstream mijn-bureau-infra Helmfile to deploy Mijn Bureau onto the
single-node K3s cluster in the Ubuntu VM.

Approach:

- Use mijn-bureau-infra at the pinned revision (`b2ae545…`, 2026-07-27;
  `manifest/appliance-manifest.json`, `docs/upstream/revisions.md`) via its
  documented Helmfile / `scripts/single-vps-deploy/` path, with the sub-scripts
  taken from that revision, never from a live URL. Pinned tooling: Helmfile
  `1.1.7`, cert-manager `v1.16.2`.
- Local-demo TLS/DNS instead of Let's Encrypt: `tls.selfSigned: true` + local
  name resolution (OQ-3, `docs/open-questions.md`).
- Generate `MIJNBUREAU_MASTER_PASSWORD` at install time; never commit secrets.
- Digest-pin container images (OQ-5).

This directory will hold only our environment values / overrides and the driver
glue, not a copy of upstream.
