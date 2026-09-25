# Ubuntu 24.04 VM (Slice 4, not implemented yet)

The single guest VM that runs single-node K3s + Mijn Bureau.

Planned contents:

- libvirt domain definition (KVM), sized for Mijn Bureau (>= 12 vCPU,
  >= 48 GiB RAM; OQ-2 in `docs/open-questions.md`).
- cloud-init to prepare the guest and trigger the K3s bootstrap (`k8s/`).
- A pinned Ubuntu 24.04 cloud image (concrete release + SHA-256; OQ-6). The
  image is downloaded and verified at install time, not committed.

The NixOS side (registering the domain with libvirtd, autostart) lands in
`hosts/appliance/virtualisation.nix`.
