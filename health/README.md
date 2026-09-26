# Health check and browser-open step (Slice 7)

The last two entries of the install plan (`manifest/appliance-manifest.json`):
"wait until Mijn Bureau is healthy" and "open Mijn Bureau in the browser".
Both run on the appliance **host**, as the logged-in `dawo` user; neither
needs root. The scripts are written and tested (offline) here; wiring them into
the host configuration is the Slice 7 integration work listed at the end.

| File | Purpose |
| --- | --- |
| `dawo-appliance-health.sh` | The check. `--once` reports and exits 0/1; `--wait [--timeout N]` polls until healthy; `--json` for machines. |
| `dawo-appliance-open-dashboard.sh` | Waits for health (bounded), then `xdg-open https://bureaublad.dawo.internal`; on timeout shows a kdialog listing the failing checks. |
| `../tests/test-health-check.sh` | Offline test with fake `ssh`/`curl`/`resolvectl`/`xdg-open`/`kdialog`. |

## What is checked and why

The criteria are those of ADR 0004, section "Health check (Slice 7) gates the
browser" (`docs/adr/0004-local-dns-and-tls.md`). Each line of the report is one
check, in dependency order:

| Check | Criterion (ADR 0004) | How | Not-OK meaning |
| --- | --- | --- | --- |
| `dns` | `resolvectl query bureaublad.dawo.internal` returns the VM address | `resolvectl query`, fallback `getent hosts`; must equal `192.168.150.10` | WAIT: no answer (routing domain not up). FAIL: another address. |
| `guest` | (prerequisite) the VM is up | `ssh -i /var/lib/dawo-appliance/ssh/id_ed25519 ops@192.168.150.10 true`; `ping` only to phrase the reason | WAIT: booting. FAIL: key not readable. |
| `node` | (prerequisite) single-node K3s | `k3s kubectl get node --no-headers`, every STATUS `Ready` | WAIT |
| `clusterissuer` | `ClusterIssuer dawo-appliance-ca` Ready | `k3s kubectl get clusterissuer dawo-appliance-ca --no-headers`, READY column `True` | WAIT |
| `certificates` | all Certificates Ready with a **stable count** | `k3s kubectl get certificate -A --no-headers`, READY (`$3`) `True` for every row, and the row count unchanged over two consecutive comparisons: upstream's `wait_for_certs` (mijn-bureau-infra `b2ae545`, `scripts/single-vps-deploy/install.sh`) | WAIT: `n/m Ready` or count still settling |
| `cert_issuers` | each Certificate issued by `dawo-appliance-ca` | `-o custom-columns=KIND:.spec.issuerRef.kind,NAME:.spec.issuerRef.name`, every row `ClusterIssuer dawo-appliance-ca` | FAIL: a chart minted its own certificate (`tls.selfSigned`) or the annotation is wrong |
| `https_dashboard` | `curl --cacert ca.crt` gets HTTP 200 from `https://bureaublad.dawo.internal/` | `curl --cacert /var/lib/dawo-appliance/ca/ca.crt` | WAIT: 404/502/503, refused, timeout. FAIL: certificate not trusted by the CA (curl 60). |
| `https_oidc` | HTTP 200 from Keycloak's `/realms/mijnbureau/.well-known/openid-configuration`, `issuer` equals the configured one | same `curl`; `issuer` parsed with `jq`, else `python3`, else `sed`; must be `https://id.dawo.internal/realms/mijnbureau` | WAIT: Keycloak starting. FAIL: issuer differs (`global.domain` / `authentication.oidc` mismatch, which breaks every OIDC app). |
| `browser_trust` | Firefox policy file present and installing the CA | `/etc/firefox/policies/policies.json` mentions the CA path (`hosts/appliance/appliance-ca.nix` writes `Certificates.Install`) | FAIL (build-time file; waiting will not help) |

Why the certificate count must be stable: cert-manager creates a `Certificate`
per Ingress as Helmfile rolls the apps out, so "all Ready" is true too early
(2 of 2 Ready while 17 more are still to be created). Upstream therefore only
proceeds once the count has not changed over consecutive polls; the appliance
does the same before restarting nothing but the browser.

`WAIT` means the deployment is still converging; `FAIL` means a configuration
problem that time will not fix. `--wait` keeps polling on `FAIL` as well
(early-boot states can look like a FAIL for one poll); the final report shows
what remained.

Not checked here (recorded in ADR 0004): the Chromium NSS entry. It is created
per login by `dawo-appliance-ca-nss.service` (a user unit) and asserted by the
NixOS boot test, not by this script, which stays browser-agnostic beyond the
policy file.

## Running it on the host

```sh
# One report, exit 0 when healthy:
bash /path/to/health/dawo-appliance-health.sh --once
# Poll (progress on stderr, final report on stdout), give up after 30 minutes:
bash /path/to/health/dawo-appliance-health.sh --wait --timeout 1800
# Machine-readable:
bash /path/to/health/dawo-appliance-health.sh --once --json
# The full last step: wait, then open the browser (or show what is missing):
bash /path/to/health/dawo-appliance-open-dashboard.sh
```

Example report:

```
OK   dns              bureaublad.dawo.internal -> 192.168.150.10
OK   guest            ssh ops@192.168.150.10 accepts the appliance key
OK   node             1/1 node(s) Ready (dawo-appliance-mb)
OK   clusterissuer    ClusterIssuer dawo-appliance-ca Ready
WAIT certificates    12/19 Certificates Ready
OK   cert_issuers     19/19 Certificates issued by ClusterIssuer/dawo-appliance-ca
WAIT https_dashboard  https://bureaublad.dawo.internal/ -> HTTP 404
WAIT https_oidc       https://id.dawo.internal/realms/mijnbureau/.well-known/openid-configuration: connection refused (ingress not listening yet)
OK   browser_trust    Firefox policy /etc/firefox/policies/policies.json installs /var/lib/dawo-appliance/ca/ca.crt
```

JSON shape: `{"healthy": bool, "mode": "once|wait", "elapsed_seconds": n,
"dashboard_url": "...", "checks": {"<name>": {"status": "OK|WAIT|FAIL", "ok":
bool, "reason": "..."}}}`.

### Exit codes

| Script | 0 | 1 | 2 |
| --- | --- | --- | --- |
| `dawo-appliance-health.sh` | healthy | not (yet) healthy, or `--wait` timed out | usage error |
| `dawo-appliance-open-dashboard.sh` | dashboard opened | not healthy within the timeout (dialog shown) | browser could not be started |

### Configuration (environment, all optional)

Defaults follow the manifest and ADR 0004; override for another domain,
address or key. `HEALTH_CA_CERT` defaults to `DAWO_APPLIANCE_CA_CERT` from
`/etc/dawo-appliance/ca.env` when that file exists, else
`/var/lib/dawo-appliance/ca/ca.crt`.

- Targets: `HEALTH_BASE_DOMAIN` (`dawo.internal`), `HEALTH_DASHBOARD_HOST`,
  `HEALTH_ID_HOST`, `HEALTH_REALM` (`mijnbureau`), `HEALTH_DASHBOARD_URL`,
  `HEALTH_OIDC_URL`, `HEALTH_EXPECTED_ISSUER`, `HEALTH_VM_IP`
  (`192.168.150.10`), `HEALTH_VM_USER` (`ops`), `HEALTH_SSH_KEY`,
  `HEALTH_KUBECTL` (`k3s kubectl`), `HEALTH_CLUSTER_ISSUER`
  (`dawo-appliance-ca`), `HEALTH_CA_CERT`, `HEALTH_CA_ENV`,
  `HEALTH_FIREFOX_POLICY`.
- Timing: `HEALTH_TIMEOUT` (1800), `HEALTH_POLL_INTERVAL` (15, as upstream),
  `HEALTH_CERT_STABLE_POLLS` (2 comparisons, as upstream), `HEALTH_CERT_SETTLE`
  (5 s between the extra certificate polls of `--once`), `HEALTH_SSH_TIMEOUT`,
  `HEALTH_CURL_TIMEOUT`.
- Commands (for tests): `HEALTH_SSH`, `HEALTH_CURL`, `HEALTH_RESOLVE`,
  `HEALTH_GETENT`, `HEALTH_PING`; for the opener `DASHBOARD_URL`,
  `DASHBOARD_TIMEOUT`, `DASHBOARD_HEALTH`, `DASHBOARD_XDG_OPEN`,
  `DASHBOARD_KDIALOG`, `DASHBOARD_LOG`.

## Tests

```sh
bash tests/test-health-check.sh
```

Offline: no Nix, root, network or VM. Fakes for `ssh`, `curl`, `resolvectl`,
`ping`, `xdg-open` and `kdialog` live in a temp dir; scenarios are selected with
`FAKE_SCENARIO`. Covered: all-OK (human and JSON), certificates pending (`WAIT`,
exit 1), OIDC issuer mismatch (`FAIL`), certificates that become Ready after
two polls (`--wait --timeout 3` succeeds only after the count is stable),
`--wait` timeout, wrong DNS answer, the opener in both outcomes, and that every
`curl` call carried `--cacert`. Passes on Windows Git Bash and on WSL/Linux.
Lint: `shellcheck health/*.sh tests/test-health-check.sh`.

## Integration points for Slice 7

Wired 2026-09-25 (`hosts/appliance/appliance-services.nix`,
`hosts/appliance/guest-vm.nix`); **unverified — no Nix on the machine that did
this wiring, so none of it has run through `nix flake check` or a boot test
yet.** `dawo-appliance-health.sh` and `dawo-appliance-open-dashboard.sh`
themselves are untouched.

1. **Autostart.** ✅ Done. Same pattern as the welcome dialog in
   `hosts/appliance/appliance-services.nix`, one phase later
   (`X-KDE-autostart-phase=2`) so the welcome dialog shows first: a second
   `environment.etc."xdg/autostart/dawo-appliance-open-dashboard.desktop"`
   entry, `Exec` pointing at the packaged opener below. Both scripts are
   packaged with `pkgs.writeShellApplication` (`runtimeInputs = [ openssh curl
   systemd glibc iputils jq xdg-utils kdePackages.kdialog ]`), read by path
   (`builtins.readFile`) so the tested `.sh` files stay the single source of
   truth — never hand-copied into the Nix module. The opener defaults
   `DASHBOARD_HEALTH` to the packaged health binary (its own store path differs
   from the health script's, so the opener's "next to this file" default would
   otherwise miss it) and `DASHBOARD_LOG` to
   `$XDG_STATE_HOME/dawo-appliance/health.log`. Both binaries are also on
   `$PATH` via `environment.systemPackages` for manual/debugging use.
   `DASHBOARD_TIMEOUT` is still the script's own default (1800 s); making it
   larger on first boot, or restarting the opener from a systemd user timer, is
   still open follow-up work, not done in this pass.
2. **Package both scripts.** ✅ Done as above, in
   `hosts/appliance/appliance-services.nix`.
3. **SSH key contract.** ✅ Done: the key
   (`/var/lib/dawo-appliance/ssh/id_ed25519` — see
   `hosts/appliance/guest-vm.nix`) is now `0600` owned by `dawo` instead of
   `0600 root:root` (an earlier `0640 root:libvirtd` made OpenSSH refuse the
   key for root, #75); its directory is `0750 root:libvirtd` instead of `0700
   root:root`. `dawo` already joins `libvirtd`
   (`hosts/appliance/virtualisation.nix`), so no new group was introduced —
   **demo posture, not production**, recorded as a deviation in
   `docs/adr/0003-workplace-parity.md`, the same way the generated install
   password is. The guest must still have the matching public key for `ops` in
   its cloud-init user-data, `k3s kubectl` usable by `ops`
   (`--write-kubeconfig-mode 644` is already in the manifest), and its host key
   should be pre-seeded in a known_hosts file (the script uses
   `StrictHostKeyChecking=accept-new` until then) — unchanged, still true.
4. **Welcome dialog text.** ✅ Done: "Mijn Bureau follows in a later version"
   (and its Dutch equivalent) replaced with a static message that Mijn Bureau
   deploys automatically and the dashboard opens once healthy. Wiring the live
   health `--json` output into the dialog text is still out of scope for this
   pass (a static message is enough for a demo).
5. **Makefile / verify.** Still open: add `tests/test-health-check.sh` to
   `make test` and `health/*.sh` to `SHELL_SCRIPTS` for `make lint`.
   `docs/testing.md` now maps requirement R23 ("opens the dashboard only when
   healthy") to this test.
