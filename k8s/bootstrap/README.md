# Single-node K3s bootstrap (Slice 5, not implemented yet)

Installs and starts single-node K3s inside the Ubuntu 24.04 guest.

- Pins an exact K3s release (version + checksum; OQ-6 in
  `docs/open-questions.md`). Upstream installs K3s unpinned from `get.k3s.io`;
  we do not.
- Mirrors the single-node workarounds from mijn-bureau-infra
  `scripts/single-vps-deploy/` (CoreDNS hairpin rewrite, egress policies) at
  the pinned upstream revision.
