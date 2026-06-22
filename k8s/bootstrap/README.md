# Single-node K3s bootstrap

Installs/starts single-node K3s inside the Ubuntu 24.04 guest (Slice 5).

Will pin an exact K3s release (version + checksum — `docs/open-questions.md`
OQ-6). Upstream reference points: KIND/K8s node image `v1.34.0`, cert-manager
`v1.16.2`. Mirrors the relevant single-node workarounds from
mijn-bureau-infra `scripts/single-vps-deploy/` (CoreDNS hairpin rewrite, egress
policies) at the pinned upstream revision.

Not implemented yet.
