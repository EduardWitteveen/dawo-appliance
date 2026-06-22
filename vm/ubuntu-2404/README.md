# Ubuntu 24.04 VM

The single guest VM that runs single-node K3s + Mijn Bureau (Slice 4).

Planned contents:
- libvirt domain definition (KVM), sized for Mijn Bureau (>= 12 vCPU,
  >= 48 GiB RAM — see `docs/open-questions.md` OQ-2).
- cloud-init to prepare the guest and trigger the K3s bootstrap.
- A pinned Ubuntu 24.04 cloud image (concrete release + SHA-256 — OQ-6).

The image is downloaded/verified at install time, not committed. Not
implemented yet.
