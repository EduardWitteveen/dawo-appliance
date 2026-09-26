# Pins: Ubuntu 24.04 cloud image and K3s (OQ-6)

Research record for the two `pending-pin` entries in
`manifest/appliance-manifest.json` (`vm.image`, `kubernetes.version`). Facts
checked **2026-09-25** against the official sources below. Bumping a pin means
re-running the verification commands and updating this file.

## 1. Ubuntu 24.04 LTS (noble) cloud image — KVM/libvirt

Index: <https://cloud-images.ubuntu.com/releases/noble/>. `release/` is a moving
symlink (pointed at serial `20260911` on the check date); `/noble/current/` is
daily builds. **Pin the dated directory**, never `release/` or `current/`.

| Item | Value |
|------|-------|
| Directory | `release-20260911` (published 2026-09-11 22:31 UTC) |
| File | `ubuntu-24.04-server-cloudimg-amd64.img` (qcow2, cloud-init), 625 256 960 bytes |
| SHA-256 | `612b2c0cc1bc413a6cb8c38fd611794caf0f2b436c50013d8b3794db12ad7354` |
| `SHA256SUMS` | SHA-256 `89be81c6f31ffcd63e9df433e868fc2a651475a45aeb993c0dbd2707747b0185` |
| `SHA256SUMS.gpg` | 833 bytes, detached RSA signature made 2026-09-11 |
| Signing key | `D2EB 4462 6FDD C30B 513D 5BB7 1A5D 6C4C 7DB8 7C81` — "UEC Image Automatic Signing Key <cdimage@ubuntu.com>" (keyserver.ubuntu.com) |

URL scheme: `https://cloud-images.ubuntu.com/releases/noble/release-$SERIAL/<file>`
for the image, `SHA256SUMS` and `SHA256SUMS.gpg`. Verified locally on
2026-09-25: `gpg` reports *Good signature* from the key above; the image line
matches the table.

```sh
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys D2EB44626FDDC30B513D5BB71A5D6C4C7DB87C81
gpg --verify SHA256SUMS.gpg SHA256SUMS
sha256sum --ignore-missing -c SHA256SUMS      # lines use "*file" (binary mode); fine
echo "612b2c0c...7354 *ubuntu-24.04-server-cloudimg-amd64.img" | sha256sum -c
```

## 2. K3s release

### What Mijn Bureau (`b2ae545`, 2026-07-27) requires

- **No `kubeVersion`** in any `helmfile/apps/*/charts/*/Chart.yaml`, except
  `ollama` (`^1.16.0-0`), which the single-VPS path disables.
- Upstream's own test cluster (`scripts/kind.sh`) uses `kindest/node:v1.34.0`
  and Traefik chart `40.3.0` (Traefik v3.7.4, `kubeVersion >=1.25.0-0`). On K3s
  the bundled Traefik is used (`02-networking.sh` targets `traefik.kube-system`).
- `01-deploy.sh` installs K3s from `get.k3s.io` **unpinned** (channel `stable`)
  and applies **cert-manager v1.16.2**, which officially supports Kubernetes
  1.25 → 1.32 and has been EOL since 2025-06-10 (current 1.21: 1.33 → 1.36). The
  Kubernetes deprecation guide lists no API removals after v1.32, so 1.16.2
  runs on 1.33–1.37 in practice, but outside its support window (risk 1).

### K3s lines on 2026-09-25 (github.com/k3s-io/k3s, update.k3s.io channels)

| Line | Newest stable | Kubernetes maintenance EOL |
|------|---------------|----------------------------|
| v1.34 | `v1.34.11+k3s1` (upstream's KIND version) | 2026-10-27 |
| v1.35 | `v1.35.8+k3s1` | 2027-02-28 |
| **v1.36** | **`v1.36.4+k3s1`** = channel **`stable`** | 2027-06-28 |
| v1.37 | `v1.37.0+k3s1` (2026-09-14) = channel `latest`; `.1` at rc2 | 2027-10-28 |

### Chosen pin: `v1.36.4+k3s1`

It is exactly what upstream's documented path yields today (channel `stable`),
the charts have no version ceiling, 1.36 is supported until mid-2027, v1.34
reaches EOL in a month, and v1.37.0 is an eleven-day-old `.0` with a patch in rc.

| Item | Value |
|------|-------|
| Tag | `v1.36.4+k3s1`, published 2026-08-27T15:53:55Z, `prerelease: false` |
| Components | Kubernetes v1.36.4, containerd v2.3.4-k3s1.36, runc v1.4.2, Flannel v0.28.4, Traefik v3.7.8, CoreDNS v1.14.6, etcd v3.6.14-k3s1, Kine v0.16.4 |
| `k3s` (amd64) | 78 991 522 bytes — `835873f37245fc615f547a2fe2af9402a347875f13fa64a1f136de644955ea3f` |
| `k3s-airgap-images-amd64.tar.zst` (optional) | 193 436 957 bytes — `9024613e2d468c51ba0e5ba21898604c41339354449fb3338cc6a7931189eb6a` |
| `install.sh` at the tag | 37 118 bytes — `46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad` |

Official `sha256sum-amd64.txt` for `v1.36.4+k3s1`:

```
f94b5be3d3403ee6aa9b374d0eb9c91abce4347b7fe6422c317f93ada6da08a0  k3s-airgap-images-amd64.tar
a5a6c970a992ce6ed5801b5fd090aa7edde354a786eb0e7d75b162d0b22901dd  k3s-airgap-images-amd64.tar.gz
9024613e2d468c51ba0e5ba21898604c41339354449fb3338cc6a7931189eb6a  k3s-airgap-images-amd64.tar.zst
835873f37245fc615f547a2fe2af9402a347875f13fa64a1f136de644955ea3f  k3s
```

URLs: `https://github.com/k3s-io/k3s/releases/download/v1.36.4+k3s1/<asset>`
(`+` literal or `%2B`); `https://raw.githubusercontent.com/k3s-io/k3s/v1.36.4%2Bk3s1/install.sh`.

```sh
sha256sum --ignore-missing -c sha256sum-amd64.txt     # k3s (+ airgap tarball if fetched)
echo "835873f3...ea3f  k3s" | sha256sum -c            # pinned value from the manifest
echo "46177d4c...bfad  install.sh" | sha256sum -c
```

### Install method (pinned, no channel lookup)

`install.sh` verifies the binary against `sha256sum-<arch>.txt` itself, but only
after resolving a version. Either `INSTALL_K3S_VERSION=v1.36.4+k3s1` (skips the
channel lookup; still fetches binary and hash from GitHub at run time), or —
**preferred** — pre-download `k3s`, verify it against the manifest, place it at
`/usr/local/bin/k3s` and run the pinned `install.sh` with
`INSTALL_K3S_SKIP_DOWNLOAD=true` (nothing fetched). Airgap variant: unpack the
`.tar.zst` into `/var/lib/rancher/k3s/agent/images/`. Keep upstream's
`INSTALL_K3S_EXEC="--write-kubeconfig-mode 644"`; run the script from a verified
local copy, never `curl … | sh`. `INSTALL_K3S_SKIP_START`/`SKIP_ENABLE` exist if
the appliance manages the unit itself.

### Ubuntu 24.04 specifics

- **SELinux:** n/a. `k3s-selinux` is an RPM for RHEL-family hosts; the script
  skips it when `/usr/share/selinux` is absent (`INSTALL_K3S_SKIP_SELINUX_RPM=true`
  is harmless). AppArmor needs no profile for a normal (non-rootless) install.
- **iptables:** noble ships `iptables 1.8.10-3ubuntu2` (nft backend), outside
  the known-bad 1.8.0–1.8.4 range; K3s bundles 1.8.8 (`--prefer-bundled-bin`
  if the host copy ever misbehaves). No legacy-mode switch needed.
- **ufw:** present but inactive in the cloud image; leave it off or allow
  6443/tcp, 10250/tcp and the pod/service CIDRs (10.42.0.0/16, 10.43.0.0/16).

## Open risks

1. **cert-manager v1.16.2 is EOL and unsupported on Kubernetes 1.36.**
   Decided (#10, maintainer 2026-09-26): follow upstream exactly (v1.16.2).
   The first real deploy must prove it with a check (cert-manager pods Ready,
   a `Certificate` issued). Only if that fails: pin a supported line (1.21.x)
   as a deviation with an ADR (`docs/deviations.md` D15).
2. Upstream tests on KIND 1.34, not 1.36; the Slice 5/6 end-to-end run is the
   real compatibility check.
3. Ubuntu serials are re-published every few weeks (old ones still served, back
   to 20240423); K3s `v1.36.5+k3s1` is at rc2. Expect bumps after Slice 5; keep
   a local copy of image + checksums. GPG trust is by pinned fingerprint only.

## Manifest snippet (ready to paste; the manifest is edited elsewhere)

```json
"vm": { "image": {
  "status": "pinned", "distribution": "Ubuntu 24.04 LTS (noble) server cloud image",
  "serial": "20260911",
  "base_url": "https://cloud-images.ubuntu.com/releases/noble/release-20260911/",
  "file": "ubuntu-24.04-server-cloudimg-amd64.img", "size_bytes": 625256960,
  "sha256": "612b2c0cc1bc413a6cb8c38fd611794caf0f2b436c50013d8b3794db12ad7354",
  "sha256sums_sha256": "89be81c6f31ffcd63e9df433e868fc2a651475a45aeb993c0dbd2707747b0185",
  "gpg_fingerprint": "D2EB44626FDDC30B513D5BB71A5D6C4C7DB87C81", "inspected": "2026-09-25"
} },
"kubernetes": { "version": {
  "status": "pinned", "tag": "v1.36.4+k3s1", "kubernetes": "v1.36.4", "released": "2026-08-27",
  "download_base": "https://github.com/k3s-io/k3s/releases/download/v1.36.4+k3s1/",
  "binary": { "name": "k3s", "size_bytes": 78991522,
    "sha256": "835873f37245fc615f547a2fe2af9402a347875f13fa64a1f136de644955ea3f" },
  "checksums_file": "sha256sum-amd64.txt",
  "airgap_images_zst_sha256": "9024613e2d468c51ba0e5ba21898604c41339354449fb3338cc6a7931189eb6a",
  "install_script": { "url": "https://raw.githubusercontent.com/k3s-io/k3s/v1.36.4%2Bk3s1/install.sh",
    "sha256": "46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad",
    "env": { "INSTALL_K3S_SKIP_DOWNLOAD": "true", "INSTALL_K3S_EXEC": "--write-kubeconfig-mode 644" } },
  "inspected": "2026-09-25"
} }
```
