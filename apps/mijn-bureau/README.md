# Mijn Bureau deployment

Drives the upstream mijn-bureau-infra Helmfile to deploy Mijn Bureau onto the
single-node K3s cluster (Slice 6).

Approach:
- Use mijn-bureau-infra at pinned rev `ef1d796211ad8624ad5a78cb9a828b0926c2933b`
  via its documented Helmfile / `scripts/single-vps-deploy/` path. Pinned
  tooling: Helmfile `1.1.7`, cert-manager `v1.16.2`.
- Local-demo TLS/DNS instead of Let's Encrypt: `tls.selfSigned: true` + local
  name resolution (`docs/open-questions.md` OQ-3).
- Generate `MIJNBUREAU_MASTER_PASSWORD` at install time; never commit secrets.
- Digest-pin container images (OQ-5).

This directory will hold only our environment values / overrides and the driver
glue — not a copy of upstream. Not implemented yet.
