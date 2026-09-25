# ADR 0004: Local DNS and TLS for the Mijn Bureau demo (OQ-3)

- Status: Accepted (2026-09-25, maintainer: base domain `dawo.internal`; the rest as proposed)
- Date: 2026-09-25
- Deciders: maintainer (eywitteveen)

## Context

Mijn Bureau's documented single-node path (mijn-bureau-infra `b2ae545`,
`docs/docs/getting_started/single-vps-k3s.md`, `scripts/single-vps-deploy/`)
assumes a public wildcard record `*.DOMAIN` and Let's Encrypt: `01-deploy.sh`
installs cert-manager `v1.16.2` with a `ClusterIssuer letsencrypt-prod`
(http01 via Traefik) and writes `helmfile/environments/demo/mijnbureau.yaml.
gotmpl` with `global.domain`, `cluster.routingMode: ingress`,
`cluster.ingress.type: traefik`, `cluster.ingress.annotations:
cert-manager.io/cluster-issuer`, and `authentication.oidc.*` pinned to
`https://id.DOMAIN/realms/mijnbureau`. The
appliance has no public domain (`docs/purpose.md`), so Slices 6 and 7 need a
self-contained replacement. Facts that constrain the choice:

- **Hostnames.** One base domain plus the `global.hostname.*` labels
  (`helmfile/environments/default/global.yaml.gotmpl`, `docs/docs/dns.md`):
  `id` (Keycloak), `bureaublad`, `nextcloud`, `collabora`, `element`,
  `matrix`, `meet`, `livekit`, `docs`, `grist`, `drive`, `conversations`,
  `openproject`, and the static/minio helpers `static-{conversations,drive,
  meet,docs,grist}`, `drive-minio`. A wildcard covers all of them.
- **In-cluster HTTPS is mandatory.** Every OIDC client (Grist, Docs, Meet,
  Drive, Conversations, Bureaublad backends, Nextcloud, Synapse) fetches
  Keycloak's discovery document server-side over `https://id.DOMAIN`; Collabora
  talks WOPI to `https://nextcloud.DOMAIN`. Upstream rewrites `*.DOMAIN` in
  CoreDNS to the in-cluster Traefik service (`02-networking.sh`) and restarts
  the OIDC apps only once `kubectl get certificate -A` is all Ready
  (`install.sh`, `03-restart-oidc-apps.sh`). So the certificate must be
  trusted **inside the pods**, not only by the host browser.
- **`global.tls.selfSigned: true` is not a CA.** Each chart then mints its own
  Helm `genCA` + `genSignedCert` per hostname (e.g. `helmfile/apps/grist/charts/
  grist/templates/tls-secret.yaml`; wired via `ingress.selfSigned` in every
  `helmfile/apps/*/values*.yaml.gotmpl`), suppresses HSTS
  (`helmfile/apps/common/charts/common/templates/_ingress.tpl`) and writes the
  secret `<hostname>-tls`, the same name cert-manager would use. It yields
  ~19 unrelated CAs, browser warnings and failing OIDC discovery.
- **Upstream's own local path does not rely on it.** `scripts/kind.sh` installs
  a mkcert CA on the developer host, issues one wildcard `*.127.0.0.1.sslip.io`
  cert and makes it Traefik's default `TLSStore` certificate; CoreDNS rewrites
  the domain to Traefik. That is "one trusted local CA + wildcard resolution",
  which is what we need, minus mkcert and minus the sslip.io dependency.
- **No app-level trust knob exists upstream.** No `NODE_EXTRA_CA_CERTS`,
  `REQUESTS_CA_BUNDLE`, `SSL_CERT_FILE` or CA-bundle value is set anywhere in
  `helmfile/apps/`. Available hooks: charts expose `extraEnvVars`,
  `extraVolumes`, `extraVolumeMounts`; the Keycloak chart has
  `trustedCertsExistingSecret` (mounted as `KC_TRUSTSTORE_PATHS`); Nextcloud has
  `occ security:certificates:import`; Collabora takes `extra_params`.
- **Host side (DAWO-Core 0.1.3, unchanged per ADR 0003).** `networking-client`
  uses NetworkManager with `dns = "systemd-resolved"`, networkd and nftables.
  Firefox is built `--with-system-nss`; nixpkgs' NSS replaces `libnssckbi`
  with p11-kit-trust, and Chromium uses system NSS, so both read
  `/etc/ssl/trust-source`. But `security.pki.certificateFiles` is resolved at
  **build** time, while our CA is generated at **install** time, so trust
  must be established at run time. Firefox policy `Certificates.Install`
  accepts an absolute path (Firefox >= 65); `ImportEnterpriseRoots` is
  Windows/macOS only. Chromium on Linux has no certificate policy; it reads
  the per-user NSS database `~/.pki/nssdb`.
- The VM sits on a libvirt NAT network (`hosts/appliance/virtualisation.nix`),
  whose dnsmasq already serves DHCP and DNS to the guest.

## Decision

1. **Base domain `dawo.internal`** (maintainer's choice: short, matches the host name `dawo-appliance`; `mb.appliance.internal` was the draft). `.internal` is reserved for
   private use (ICANN, 2024) and never resolves publicly; `.local` is mDNS
   (Avahi/systemd-resolved) and is avoided; `.home.arpa` is for home networks
   and reads oddly in a demo. The `mb.` label leaves room for other profiles
   (`apps/profiles/`). Recorded in `manifest/appliance-manifest.json`
   (`mijn_bureau.base_domain`); the dashboard URL becomes
   `https://bureaublad.dawo.internal`.
2. **Name resolution: libvirt's dnsmasq is the single authority.** The
   appliance defines its own libvirt network `dawo-appliance` (NAT, fixed
   subnet, e.g. `192.168.150.0/24`), a fixed DHCP lease for the VM
   (`192.168.150.10`) and the wildcard `address=/dawo.internal/
   192.168.150.10` via libvirt's `<dnsmasq:options>` namespace.
   - **Guest:** gets the same dnsmasq via DHCP, so the K3s node resolves the
     names. **Pods:** keep upstream's CoreDNS rewrite of `*.DOMAIN` to the
     Traefik service (`02-networking.sh`), which avoids NAT hairpin; the
     8443 egress policies and LiveKit `node_ip` fix apply unchanged.
   - **Host:** a systemd-resolved routing domain `~dawo.internal` with
     DNS `192.168.150.1` on the bridge interface (set from a libvirt network
     hook or a networkd `.network` unit matched on the bridge; Slice 4 picks
     the one that survives NetworkManager). Nothing else on the host resolver
     changes. The host reaches the VM directly on the bridge (443, 80, UDP
     30001-30009 for LiveKit), so no port forwarding is needed.
3. **TLS: one per-install appliance CA, issued through cert-manager.**
   - `dawo-appliance-bootstrap install` (or a first-boot service) generates a
     CA (`/var/lib/dawo-appliance/ca/ca.{crt,key}`, key root-only, valid 10
     years, CN "DAWO appliance local CA"). It is never in Git or in the ISO: a
     CA shared by all installations would let anyone with the image
     impersonate every appliance.
   - The key and certificate reach the VM once, through the install-time
     cloud-init user-data (root, mode 0600, same channel as the master
     password). Cloud-init `ca_certs` adds the CA to the Ubuntu node trust
     store; the K3s bootstrap creates `Secret dawo-appliance-ca` in
     `cert-manager` and a `ClusterIssuer dawo-appliance-ca` of kind CA.
   - Mijn Bureau values: `global.tls.enabled: true`, **`selfSigned: false`**,
     `cluster.ingress.annotations: cert-manager.io/cluster-issuer:
     dawo-appliance-ca`, `cluster.ingress.type: traefik`, and the same
     `authentication.oidc` block as `01-deploy.sh`. Every Ingress then gets a
     cert-manager `Certificate` exactly as on the Let's Encrypt path; HSTS
     stays on, which is correct because the CA is trusted.
   - **In-cluster trust** is a post-deploy step in `apps/mijn-bureau/`, using
     upstream's own technique (`03-restart-oidc-apps.sh`: patch, then rollout
     restart): a ConfigMap with `ca.crt` in each `mb-*` namespace, mounted and
     announced per runtime (`NODE_EXTRA_CA_CERTS` for Node.js apps such as
     Grist; `SSL_CERT_FILE` and `REQUESTS_CA_BUNDLE` for the Python/Django
     backends and Synapse; Nextcloud `occ security:certificates:import`;
     Collabora `--o:ssl.ca_file_path`; Keycloak `trustedCertsExistingSecret`
     for back-channel logout). The exact knob list is a Slice 6 deliverable
     and is verified per app. **Verification is never disabled** (no
     `NODE_TLS_REJECT_UNAUTHORIZED=0` or `verify: false`).
   - **Host trust (run time, additions only):** `programs.firefox.policies.
     Certificates.Install = [ "/var/lib/dawo-appliance/ca/ca.crt" ]` (merges
     with upstream's policy set); for Chromium an idempotent login hook runs
     `certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -i ca.crt` for the `dawo`
     user; system tools (health check, `curl`) pass `--cacert`. The CA
     certificate is world-readable; only the key is restricted.
4. **Health check (Slice 7) gates the browser.** In the VM: `ClusterIssuer
   dawo-appliance-ca` Ready; `kubectl get certificate -A` all Ready with a
   stable count over two polls (upstream's `wait_for_certs`), each issued by
   `dawo-appliance-ca`. On the host: `resolvectl query bureaublad.dawo.internal
   ` returns the VM address; `curl --cacert ca.crt` gets HTTP 200 from
   `https://bureaublad.dawo.internal/` and from Keycloak's
   `/realms/mijnbureau/.well-known/openid-configuration` whose `issuer` equals
   the configured one; the Firefox policy file and the Chromium NSS entry are
   present. Only then the welcome hook opens the dashboard. The NixOS boot
   test asserts the resolver rule and the policy file without a cluster.

## Consequences

- `tls.selfSigned: true`, assumed in `docs/architecture.md`, OQ-3 and
  `apps/mijn-bureau/README.md`, is **wrong for us**; those texts, the manifest
  and `docs/purpose.md` ("self-signed TLS") change to "private appliance CA"
  when this ADR is accepted.
- Fully self-contained: no third party is contacted for names or certificates,
  and the demo keeps working without internet after deployment.
- We own more glue: a libvirt network definition, resolver wiring, CA
  generation and its cloud-init transport, the ClusterIssuer, per-app trust
  patches and the browser hooks. Each is small; the per-app patches are the
  fragile part and must be re-checked on every upstream bump.
- A reinstall produces a new CA; nothing outside the appliance ever trusted
  the old one. Leaf certificates renew automatically (cert-manager default).
- Security posture stays "demo, not hardened" (`docs/purpose.md`): a private
  root is trusted by the appliance's browsers only, and the key never leaves
  the host and VM. The install-time secret channel (cloud-init) now carries
  the CA key as well as the master password and must be protected the same.
- Upstream finding worth reporting: a documented private-CA path (a
  `cluster.certificate.issuerRef`-style value plus one trust-bundle knob for
  the OIDC apps) would remove most of our post-deploy patching.

## Alternatives considered

- **`/etc/hosts` generation.** Rejected: 19 names on host and VM, pods do not
  read it, breaks on every VM address or hostname change.
- **Host-only dnsmasq/resolved forwarded into the VM.** Rejected: a second
  resolver hop and two configs to align; libvirt's dnsmasq serves both sides.
- **`nip.io` / `sslip.io`** (`*.192-168-150-10.sslip.io`, as upstream's KIND
  path). Rejected for v0.1: every lookup needs internet and a third party;
  contradicts "self-contained". Kept in mind as a zero-config fallback.
- **A real domain owned by the maintainer** (public wildcard, Let's Encrypt via
  DNS-01). Rejected: public DNS and registrar credentials contradict "no public
  infrastructure, accounts or credentials" (`docs/purpose.md`).
- **`global.tls.selfSigned: true`** (per-chart Helm certificates). Rejected:
  no common CA, browser warnings per host, in-cluster OIDC discovery fails.
- **Let's Encrypt** (upstream default). Rejected: needs public DNS.
  **`*.appliance.local`** (OQ-3's example) is rejected as mDNS, see above.
- **mkcert-style single wildcard as Traefik default certificate, no
  cert-manager.** Viable and simpler, but it leaves upstream's documented path
  (cert-manager annotation, `kubectl get certificate -A` as health signal) and
  would need Traefik chart values K3s does not expose by default. Rejected;
  the CA ClusterIssuer keeps the Helmfile input identical to `01-deploy.sh`
  except for the issuer name.
- **Disabling TLS verification in the OIDC apps.** Rejected: hides exactly the
  integration problem the appliance is meant to surface.
