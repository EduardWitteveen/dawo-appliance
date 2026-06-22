# Open questions

Tracked decisions and unknowns. **Blocking** items must be resolved before the
related work can proceed; **non-blocking** items are improvements that can wait.

## OQ-1 (RESOLVED 2026-06-22): `/mnt/c` now mounts with `metadata`

**Resolution:** WSL `metadata` is enabled (Option 1 below was applied via
`/etc/wsl.conf` and a WSL restart). Verified on 2026-06-22:

- `/mnt/c` mounts with the `metadata` flag (`mount | grep ' /mnt/c '`).
- `chmod` succeeds on `/mnt/c`.
- `git init` + `git add` + `git commit` succeed on this path.

So the working tree on `/mnt/c/git/dawo-appliance` can be a real git repo. The
repo is **not yet initialised** — do that as a separate step (commits need
maintainer approval per project rules; **no remote yet**).

**Nix** is a separate matter: it is still **not installed** on this machine.
With `metadata` on, Nix can be installed and run here, but putting the Nix store
on the 9p `/mnt/c` mount is slow; prefer the default store location on the WSL
ext4 filesystem. Installing Nix is its own task, not part of OQ-1.

Historical context — the original blocker:

`/mnt/c` was mounted via 9p **without** the `metadata` option, so `chmod` failed
drive-wide, which broke `git init` and Nix store operations. Options considered:

1. Enable metadata in WSL via `/etc/wsl.conf` `[automount] options = "metadata"`,
   then `wsl --shutdown` and reopen. **(Applied — this is the resolution.)**
2. Move the working tree to the WSL/Linux filesystem. (Rejected: conflicts with
   the requested working directory.)
3. Develop on `/mnt/c` but run git/Nix elsewhere. (No longer needed.)

## OQ-2 (BLOCKING for full run, not for v0.1 dev): host RAM/CPU

Mijn Bureau single-node needs **>= 12 vCPU and >= 48 GiB RAM**. The VM running
it must be that big, so the physical host needs roughly **>= 16 vCPU /
>= 56–64 GiB RAM**. This development machine has 12 vCPU / **15 GiB RAM**, which
is enough to build and dry-run the installer but **cannot run the full stack**
(steps 7–12). Need a suitable target machine for end-to-end testing.

## OQ-3 (BLOCKING for steps 10–12): local DNS + TLS strategy

Upstream's single-VPS path uses Let's Encrypt + public DNS + email. A local
demo needs a self-contained alternative:

- `tls.selfSigned: true` (supported upstream), and
- a way to resolve `*.<base-domain>` on the host and inside the VM.

Decide the base domain (e.g. `appliance.local`) and the resolution mechanism
(host `/etc/hosts`, dnsmasq/CoreDNS, or a wildcard like `nip.io`). The browser
must trust the self-signed CA, so the host must install the generated CA into
its trust store and the browser. Needs a decision before steps 10–12.

## OQ-4 (RESOLVED 2026-06-22): license choice

**Decision: EUPL-1.2.** Chosen by the maintainer. See `LICENSE` (SPDX
`EUPL-1.2`). Rationale: aligns with Mijn Bureau (EUPL-1.2) and is compatible
with DAWO-NixOS (GPL-3.0), which the EUPL Appendix lists as a Compatible
Licence. We consume DAWO-NixOS as a flake input (aggregation); EUPL/GPL
compatibility covers the combined-distribution case.

## OQ-5 (non-blocking): image digest pinning

Upstream pins container images by **tag** (e.g. `nextcloud:34.0.0-apache`) in
`helmfile/environments/default/container.yaml.gotmpl`, not by digest. Our rules
ask for digests. Resolving every tag to a `sha256:` digest is a follow-up task;
v0.1 records tags and the upstream revision they come from, and flags this.

## OQ-6 (non-blocking): exact K3s and Ubuntu image pins

The first slice stops before the VM/K3s steps, so the manifest currently marks
the K3s release and the Ubuntu 24.04 cloud image as **unverified/pending pin**.
These must be pinned to a concrete version + SHA-256 before steps 7–9. Upstream
uses a KIND/K8s node image `v1.34.0` and Helmfile `1.1.7`, cert-manager
`v1.16.2` as reference points.

## OQ-7 (non-blocking): signature verification

Add manifest/artifact signature verification (upstream ships `cosign.pub`;
minisign is an option for our own manifest) on top of checksums. Planned
hardening, not in v0.1.

## OQ-8 (non-blocking): how to obtain the "pinned release of this repository"

The bootstrap is meant to "download a pinned release of this repository", but we
must not configure a remote yet. For now the bootstrap supports a
`--manifest-url` override (incl. `file://`) for local testing, with a clearly
marked placeholder default. The real release-hosting location (and whether it is
a tarball + checksum, a git tag, or a release asset) is undecided.

## OQ-9 (non-blocking, known issue): `appliance-disk-image` is KVM-flaky on WSL

`nix build .#appliance-disk-image` uses disko's `make-disk-image` (nixpkgs
`vmTools`), which runs a QEMU build VM. On this WSL host the build often fails
with `Could not access KVM kernel module: Permission denied`: unlike NixOS VM
tests (which declare `requiredSystemFeatures = ["kvm"]` and get proper /dev/kvm
access), the `vmTools` VM does not, so the sandboxed build user cannot open
`/dev/kvm` once the `kvm` system feature is enabled. It is environment-specific,
not a defect in the appliance config.

Impact: low. Slice 2 storage is verified without it — `diskoScript` builds (the
layout, incl. swap, applied only to the sentinel device), the appliance toplevel
builds, and `test-appliance-boot` (a NixOS VM test, which *does* get KVM) boots
the host. Options if a full image build is needed later: give `/dev/kvm` group
access inside builds, run the image build outside the Nix sandbox, or boot the
host via a NixOS VM test instead of `make-disk-image`.
