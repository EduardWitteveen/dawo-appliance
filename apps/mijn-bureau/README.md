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

## Nextcloud apps (#190, D38)

Conduction's Nextcloud apps (EUPL-1.2), pinned by release tarball and SHA-256
(`NC_APP_*` in `deploy.sh`, equal to `mijn_bureau.nextcloud_apps` in the
manifest; `tests/test-mijnbureau-driver.sh` checks both):

| App | Version | Installed | What it is |
| --- | --- | --- | --- |
| Thematiq | 1.2.10 | phase 13, both profiles | NL Design System theming (default theme) |
| OpenRegister | 2.1.0 | on request | data layer for the apps below |
| Dossiq | 0.4.0 | on request | case handling; needs OpenRegister |
| Pipelinq | 0.5.1 | on request | client and request management (CRM); needs OpenRegister |
| Portaliq | 0.2.0 | on request | portal for citizens and businesses; needs OpenRegister |

`deploy.sh --list-nc-apps` lists them; `deploy.sh --nc-app <id>` installs one
into a deployed Mijn Bureau, its dependency first (`--dry-run` works too). On
the live USB, once the status page says "klaar": `dawo-appliance-nc-app <id>`
in a terminal (no argument: the list). The verified tarball is unpacked into
`custom_apps` on the Nextcloud PVC with `kubectl exec`, then `occ app:enable`;
an app already at the pinned version is left alone, another version is
replaced and followed by `occ upgrade`. All five declare Nextcloud 32-34
(ours: 34.0.1) and PHP >= 8.3 (the image has 8.5: not yet tried on a real run).
