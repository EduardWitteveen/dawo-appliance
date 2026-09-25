# Single-node K3s bootstrap (Slice 5)

Installs and starts single-node K3s inside the Ubuntu 24.04 guest
(`dawo-appliance-mb`). Experimental and unofficial.

| File | Purpose |
|------|---------|
| `install-k3s.sh` | Self-contained bash installer: download (or take from `K3S_OFFLINE_DIR`), verify SHA-256 of both `k3s` and `install.sh`, install, wait for the node to be Ready. Idempotent. |
| `../../tests/test-k3s-install.sh` | Offline test (no network, no root): pins equal the manifest, dry run, tampered files rejected. |

Not here yet (Slice 6, `apps/mijn-bureau/`): cert-manager, the appliance CA
`ClusterIssuer` (ADR 0004), and the single-node workarounds from
mijn-bureau-infra `scripts/single-vps-deploy/02-networking.sh` (CoreDNS
hairpin rewrite to `traefik.kube-system`, 8443 egress policies, LiveKit
`node_ip`). Those need the cluster this script provides.

## Pins

Source of truth: `manifest/appliance-manifest.json`, `kubernetes.version`
(research: `docs/upstream/pins-vm-k3s.md`). The same values are baked into the
script as `DEFAULT_*` constants so the guest needs no repository checkout;
`tests/test-k3s-install.sh` fails when they drift apart.

| Item | Value |
|------|-------|
| K3s tag | `v1.36.4+k3s1` (Kubernetes v1.36.4, channel `stable` on 2026-09-25) |
| `k3s` amd64 | `835873f37245fc615f547a2fe2af9402a347875f13fa64a1f136de644955ea3f` |
| `install.sh` at the tag | `46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad` |
| Download base | `https://github.com/k3s-io/k3s/releases/download/v1.36.4+k3s1/` |
| `install.sh` URL | `https://raw.githubusercontent.com/k3s-io/k3s/v1.36.4%2Bk3s1/install.sh` |

Bumping: change the manifest (and `make manifest-sum`), the four `DEFAULT_*`
lines at the top of `install-k3s.sh`, this table, and re-run the verification
commands in `docs/upstream/pins-vm-k3s.md`.

## Deviation from upstream

mijn-bureau-infra `b2ae545`, `scripts/single-vps-deploy/01-deploy.sh` line 21:

```sh
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
```

That resolves the `stable` channel at run time and executes an unverified
script. We keep the result identical but pin and verify it:

1. `k3s` and `install.sh` are fetched for the pinned tag only (curl, 5 retries)
   or taken from `K3S_OFFLINE_DIR`.
2. Both SHA-256 sums must match the pins; a mismatch prints expected/actual and
   exits 3 before anything is written.
3. The binary goes to `/usr/local/bin/k3s` (0755), then the verified
   `install.sh` runs with `INSTALL_K3S_SKIP_DOWNLOAD=true`, so the installer
   fetches nothing (`download_and_verify` returns early and only checks the
   binary is executable). `INSTALL_K3S_SKIP_SELINUX_RPM=true` is harmless on
   Ubuntu (no `/usr/share/selinux`).
4. Server flags: upstream's `--write-kubeconfig-mode 644` unchanged, plus
   `--tls-san mb.dawo.internal` so the host can later use the kubeconfig over
   the appliance's own name (ADR 0004). **Traefik stays enabled**: upstream
   relies on the bundled Traefik (`02-networking.sh` rewrites `*.DOMAIN` to
   `traefik.kube-system.svc.cluster.local` and allows egress to it on 8443;
   `01-deploy.sh` sets `cluster.ingress.type: traefik`). Do not add
   `--disable traefik`.
5. The script waits until `k3s kubectl get node` reports `Ready` (default
   300 s) and prints `k3s --version`, `kubectl version` and the node line.

## Environment and usage

All variables are optional; defaults are the pins above.

| Variable | Default | Meaning |
|----------|---------|---------|
| `K3S_VERSION` | `v1.36.4+k3s1` | release tag |
| `K3S_BINARY_SHA256` | manifest | SHA-256 of `k3s` |
| `K3S_INSTALL_SH_SHA256` | manifest | SHA-256 of `install.sh` |
| `K3S_DOWNLOAD_BASE` | manifest | release asset base URL (trailing `/`) |
| `K3S_INSTALL_SH_URL` | derived from tag | raw `install.sh` URL (`+` -> `%2B`) |
| `K3S_TLS_SAN` | `mb.dawo.internal` | extra API-server SAN |
| `K3S_EXTRA_EXEC` | empty | extra `k3s server` flags, appended verbatim |
| `K3S_BIN_DIR` | `/usr/local/bin` | install directory |
| `K3S_OFFLINE_DIR` | empty | directory holding `k3s` and `install.sh`; no network used |
| `K3S_NODE_READY_TIMEOUT` | `300` | seconds to wait for the node |
| `K3S_DRY_RUN` | `0` | `1`: fetch/copy + verify, print the install command, exit 0; no root needed |

Arguments: `--print-pins` (effective values, one `KEY=VALUE` per line),
`--help`. Exit codes: 0 ok or already installed, 1 usage/environment,
2 download or missing file, 3 checksum mismatch, 4 install failed or node not
Ready. Every log line starts with `[install-k3s]`.

Re-running is safe: when `/usr/local/bin/k3s` already has the pinned checksum
and the `k3s` unit is active, the script only re-checks node readiness and
exits 0. If the binary matches but the unit is down, it re-runs `install.sh`
and `systemctl enable --now k3s`.

Dry run without root (what the test does):

```sh
K3S_OFFLINE_DIR=/path/with/k3s+install.sh K3S_DRY_RUN=1 bash k8s/bootstrap/install-k3s.sh
```

## How the guest calls it (wired by the VM/cloud-init work, Slice 5)

The cloud-init user-data embeds the script and runs it once; the file is the
whole dependency (bash, coreutils, curl are in the Ubuntu cloud image):

```yaml
write_files:
  - path: /usr/local/lib/dawo-appliance/install-k3s.sh
    permissions: "0755"
    content: |
      # contents of k8s/bootstrap/install-k3s.sh
runcmd:
  - [ bash, -c, "/usr/local/lib/dawo-appliance/install-k3s.sh 2>&1 | tee -a /var/log/dawo-appliance/install-k3s.log" ]
```

Result on the guest: `/usr/local/bin/{k3s,kubectl,crictl,ctr}`, systemd unit
`k3s`, kubeconfig `/etc/rancher/k3s/k3s.yaml` (mode 644, `server:
https://127.0.0.1:6443`). For the host hand-off, copy the kubeconfig over SSH
and replace `127.0.0.1` with `mb.dawo.internal` (covered by `--tls-san`) or the
VM's fixed address.

## Risks and follow-ups

- **cert-manager v1.16.2 (upstream `01-deploy.sh` line 30) is EOL and
  officially supports Kubernetes <= 1.32**, while this pin is 1.36. It runs in
  practice (no API removals after 1.32), but Slice 6 must decide to follow
  upstream exactly or pin a supported cert-manager. See
  `docs/upstream/pins-vm-k3s.md`, "Open risks".
- Upstream tests on KIND 1.34; the end-to-end run in the guest is the real
  compatibility check.
- ufw is inactive in the cloud image; if it is ever enabled, allow 6443/tcp,
  10250/tcp and the 10.42.0.0/16, 10.43.0.0/16 CIDRs.
