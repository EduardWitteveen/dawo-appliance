#!/usr/bin/env bash
#
# Mijn Bureau deployment driver for the dawo-appliance guest (Slice 6).
#
# Runs INSIDE the Ubuntu 24.04 VM after single-node K3s is up. It replaces
# upstream's scripts/single-vps-deploy/install.sh, which fetches its sub-scripts
# from a live raw URL, installs K3s/Helm/cert-manager unpinned and assumes a
# public domain with Let's Encrypt. This driver:
#
#   - obtains mijn-bureau-infra at the PINNED revision (git, verified by commit
#     hash) and runs upstream's numbered post-deploy scripts from that checkout;
#   - installs Helm, Helmfile and helm-diff from pinned release URLs, each
#     verified against a recorded SHA-256;
#   - installs cert-manager from the pinned release manifest (SHA-256 verified)
#     and creates the CA ClusterIssuer `dawo-appliance-ca` (ADR 0004);
#   - writes the demo environment values as upstream's 01-deploy.sh does, with
#     our base domain and issuer;
#   - generates MIJNBUREAU_MASTER_PASSWORD once, root-only, and reuses it;
#   - deploys with `helmfile -e demo apply`, then applies the single-node
#     workarounds, in-cluster CA trust and post-deploy fixes.
#
# Every phase is idempotent. `--dry-run` prints every action and touches
# nothing. `--phase <n|name>` runs a single phase. See README.md in this
# directory. Pins below MUST equal manifest/appliance-manifest.json.
# No offline test exists yet for this driver (unlike Slices 4a/5/7); it has
# never been run against a real cluster either.
#
# SPDX-License-Identifier: EUPL-1.2

set -euo pipefail

# ---------------------------------------------------------------------------
# Pins. Recorded 2026-09-25; see README.md for how each checksum was obtained.
# ---------------------------------------------------------------------------
readonly MB_REV="b2ae545013c153b9a3fb0aebcb51d22f348e1573"
readonly MB_REPO_URLS=(
  "https://code.overheid.nl/MinBZK/mijn-bureau-infra"
  "https://github.com/MinBZK/mijn-bureau-infra"
)
readonly MB_DOMAIN_DEFAULT="dawo.internal"
readonly CLUSTER_ISSUER="dawo-appliance-ca"
readonly CA_SECRET_NAME="dawo-appliance-ca"
readonly CA_CONFIGMAP_NAME="dawo-appliance-ca"
readonly CA_MOUNT_PATH="/etc/dawo-appliance-ca"

readonly HELMFILE_VERSION="1.1.7"
readonly HELMFILE_URL="https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz"
readonly HELMFILE_SHA256="e9d870f4e502b9f0850d7e0546cab8b418ff7f44ff4df0ed54cd3df8dfda189c"

readonly HELM_VERSION="v3.21.3"
readonly HELM_URL="https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
readonly HELM_SHA256="15e041a93a590dce8100f39385cd98c84a765c9e36aeeb9e2dc6ff9e4769e2e0"

readonly HELM_DIFF_VERSION="v3.15.10"
readonly HELM_DIFF_URL="https://github.com/databus23/helm-diff/releases/download/${HELM_DIFF_VERSION}/helm-diff-linux-amd64.tgz"
readonly HELM_DIFF_SHA256="ffeff863e4a3cbe83282a13a55ee972f7497966dfb66f326a117f9b094fff161"

readonly CERT_MANAGER_VERSION="v1.16.2"
readonly CERT_MANAGER_URL="https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
readonly CERT_MANAGER_SHA256="1d51cdecd442f1f5f89783e9e0169b95d372724da203cc75dd7a5c4e50a10ce6"

# ---------------------------------------------------------------------------
# Environment (all overridable; defaults are the guest paths).
# ---------------------------------------------------------------------------
MB_DOMAIN="${MB_DOMAIN:-${MB_DOMAIN_DEFAULT}}"
APPLIANCE_CA_DIR="${APPLIANCE_CA_DIR:-/etc/dawo-appliance}"
MB_STATE_DIR="${MB_STATE_DIR:-/var/lib/mijnbureau}"
MB_MASTER_PASSWORD_FILE="${MB_MASTER_PASSWORD_FILE:-${MB_STATE_DIR}/master-password}"
MB_SRC_DIR="${MB_SRC_DIR:-${MB_STATE_DIR}/mijn-bureau-infra}"
MB_DOWNLOAD_DIR="${MB_DOWNLOAD_DIR:-${MB_STATE_DIR}/downloads}"
MB_BIN_DIR="${MB_BIN_DIR:-/usr/local/bin}"
MB_CERT_TIMEOUT="${MB_CERT_TIMEOUT:-1800}" # seconds to wait for all certificates
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

CA_CRT="${APPLIANCE_CA_DIR}/ca.crt"
CA_KEY="${APPLIANCE_CA_DIR}/ca.key"
UPSTREAM_SCRIPTS="${MB_SRC_DIR}/scripts/single-vps-deploy"

# Namespaces used by upstream's single-VPS layout (01-deploy.sh, 02-networking.sh).
readonly MB_NAMESPACES=(mb-keycloak mb-grist mb-element mb-collabora mb-nextcloud
  mb-livekit mb-meet mb-docs mb-bureaublad)

DRY_RUN=0
PHASE=""

# ---------------------------------------------------------------------------
# Phases (order matters; numbers are stable and documented in README.md).
# ---------------------------------------------------------------------------
readonly PHASES=(
  "1:preflight:check tools, cluster, CA material"
  "2:tools:install Helm, Helmfile, helm-diff (pinned, SHA-256 verified)"
  "3:cert-manager:install cert-manager ${CERT_MANAGER_VERSION} (pinned manifest)"
  "4:issuer:create CA Secret and ClusterIssuer ${CLUSTER_ISSUER}"
  "5:password:generate or reuse MIJNBUREAU_MASTER_PASSWORD (root-only file)"
  "6:source:obtain mijn-bureau-infra at ${MB_REV:0:12} (git, hash-verified)"
  "7:values:write helmfile/environments/demo/mijnbureau.yaml.gotmpl"
  "8:deploy:helmfile -e demo apply"
  "9:networking:upstream 02-networking.sh (CoreDNS rewrite, 8443 egress, LiveKit node_ip)"
  "10:wait-certs:wait until every cert-manager Certificate is Ready"
  "11:trust:in-cluster trust of the appliance CA (ConfigMap, env, Nextcloud import)"
  "12:oidc-restart:upstream 03-restart-oidc-apps.sh (Nextcloud SSRF/proxies, restarts)"
  "13:post-fixes:upstream 04-nextcloud-office.sh, 05-docs.sh, 06-grist.sh"
  "14:sessions:Keycloak session lifetimes (07 equivalent, with --cacert)"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { printf '==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
todo() { printf '    TODO (Slice 6): %s\n' "$*"; }

# run CMD...: execute, or print in dry-run.
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: %s\n' "$*"
  else
    "$@"
  fi
}

# run_in DIR CMD...: like run, in a directory.
run_in() {
  local dir="$1"; shift
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: (cd %s && %s)\n' "${dir}" "$*"
  else
    (cd "${dir}" && "$@")
  fi
}

# apply_manifest DESCRIPTION <<EOF ... EOF : kubectl apply from stdin.
apply_manifest() {
  local desc="$1" body
  body="$(cat)"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: kubectl apply -f - (%s):\n' "${desc}"
    printf '%s\n' "${body}" | sed 's/^/    | /'
  else
    printf '%s\n' "${body}" | kubectl apply -f -
  fi
}

# write_file PATH MODE <<EOF ... EOF
write_file() {
  local path="$1" mode="$2" body
  body="$(cat)"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: write %s (mode %s):\n' "${path}" "${mode}"
    printf '%s\n' "${body}" | sed 's/^/    | /'
  else
    mkdir -p "$(dirname "${path}")"
    printf '%s\n' "${body}" >"${path}"
    chmod "${mode}" "${path}"
  fi
}

# download_verified URL SHA256 DEST: fetch once, verify, keep. Fails on mismatch.
download_verified() {
  local url="$1" sha="$2" dest="$3"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: curl -fsSL %s -o %s ; sha256sum must be %s\n' "${url}" "${dest}" "${sha}"
    return 0
  fi
  mkdir -p "$(dirname "${dest}")"
  if [[ -f "${dest}" ]] && printf '%s  %s\n' "${sha}" "${dest}" | sha256sum -c --quiet - >/dev/null 2>&1; then
    info "already downloaded and verified: ${dest}"
    return 0
  fi
  curl -fsSL "${url}" -o "${dest}.tmp"
  if ! printf '%s  %s\n' "${sha}" "${dest}.tmp" | sha256sum -c --quiet - >/dev/null 2>&1; then
    rm -f "${dest}.tmp"
    die "SHA-256 mismatch for ${url} (expected ${sha}). Refusing to continue."
  fi
  mv -f "${dest}.tmp" "${dest}"
  info "downloaded and verified: ${dest}"
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1 ($2)"; }

require_ca_files() {
  [[ -d "${APPLIANCE_CA_DIR}" ]] || die "CA directory not found: ${APPLIANCE_CA_DIR} (set APPLIANCE_CA_DIR; expected ca.crt and ca.key, delivered by the appliance host, ADR 0004)"
  [[ -s "${CA_CRT}" ]] || die "CA certificate missing or empty: ${CA_CRT}"
  [[ -s "${CA_KEY}" ]] || die "CA private key missing or empty: ${CA_KEY}"
}

# ---------------------------------------------------------------------------
# Phase 1: preflight
# ---------------------------------------------------------------------------
validate_domain() {
  [[ "${MB_DOMAIN}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] \
    || die "MB_DOMAIN is not a valid DNS name: ${MB_DOMAIN}"
}

phase_preflight() {
  log "[1/14] Preflight"
  validate_domain
  require_ca_files
  info "CA material present: ${CA_CRT}, ${CA_KEY}"
  if command -v openssl >/dev/null 2>&1; then
    if ! openssl x509 -in "${CA_CRT}" -noout -ext basicConstraints 2>/dev/null | grep -q 'CA:TRUE'; then
      warn "${CA_CRT} does not carry basicConstraints CA:TRUE; cert-manager will refuse to sign with it"
    fi
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "DRY-RUN: would check: running as root; kubectl, curl, git, tar, python3 available; node Ready"
    return 0
  fi
  [[ "${EUID}" -eq 0 ]] || die "run as root inside the guest (writes ${MB_BIN_DIR}, ${MB_STATE_DIR}, uses ${KUBECONFIG})"
  need_cmd kubectl "installed by K3s"
  need_cmd curl "apt install curl"
  need_cmd git "apt install git (cloud-init packages, Slice 4)"
  need_cmd tar "coreutils"
  need_cmd python3 "used by upstream 02-networking.sh and phase 14"
  need_cmd sha256sum "coreutils"
  [[ -r "${KUBECONFIG}" ]] || die "kubeconfig not readable: ${KUBECONFIG}"
  kubectl get nodes --no-headers 2>/dev/null | grep -q ' Ready' || die "no Ready node (is K3s up?)"
  info "cluster reachable, node Ready; domain ${MB_DOMAIN}; issuer ${CLUSTER_ISSUER}"
}

# ---------------------------------------------------------------------------
# Phase 2: tools (Helm, Helmfile, helm-diff)
# ---------------------------------------------------------------------------
installed_version() { # installed_version CMD ARGS... -> stdout or empty
  "$@" 2>/dev/null || true
}

phase_tools() {
  log "[2/14] Tools: Helm ${HELM_VERSION}, Helmfile ${HELMFILE_VERSION}, helm-diff ${HELM_DIFF_VERSION}"
  local have

  have="$(installed_version "${MB_BIN_DIR}/helm" version --template '{{.Version}}')"
  if [[ "${have}" == "${HELM_VERSION}" ]]; then
    info "helm ${HELM_VERSION} already installed"
  else
    download_verified "${HELM_URL}" "${HELM_SHA256}" "${MB_DOWNLOAD_DIR}/helm-${HELM_VERSION}-linux-amd64.tar.gz"
    run tar -xzf "${MB_DOWNLOAD_DIR}/helm-${HELM_VERSION}-linux-amd64.tar.gz" -C "${MB_DOWNLOAD_DIR}" linux-amd64/helm
    run install -m 0755 "${MB_DOWNLOAD_DIR}/linux-amd64/helm" "${MB_BIN_DIR}/helm"
  fi

  have="$(installed_version "${MB_BIN_DIR}/helmfile" --version | sed -n 's/^helmfile version v\{0,1\}//p')"
  if [[ "${have}" == "${HELMFILE_VERSION}" ]]; then
    info "helmfile ${HELMFILE_VERSION} already installed"
  else
    download_verified "${HELMFILE_URL}" "${HELMFILE_SHA256}" "${MB_DOWNLOAD_DIR}/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz"
    run tar -xzf "${MB_DOWNLOAD_DIR}/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz" -C "${MB_DOWNLOAD_DIR}" helmfile
    run install -m 0755 "${MB_DOWNLOAD_DIR}/helmfile" "${MB_BIN_DIR}/helmfile"
  fi

  # helm-diff is required by `helmfile apply`. Upstream runs `helm plugin
  # install <git url>` (unpinned) via `helmfile init`; we unpack the pinned
  # release tarball into the Helm plugin directory instead. The root helmfile
  # declares no `secrets:`, so helm-secrets is not needed.
  local plugins_dir
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    # shellcheck disable=SC2016  # literal, meant to print as the command a real run would use
    plugins_dir='$(helm env HELM_PLUGINS)'
  else
    plugins_dir="$("${MB_BIN_DIR}/helm" env HELM_PLUGINS)"
  fi
  have="$(installed_version "${MB_BIN_DIR}/helm" plugin list | awk '$1=="diff"{print $2}')"
  if [[ "v${have}" == "${HELM_DIFF_VERSION}" ]]; then
    info "helm-diff ${HELM_DIFF_VERSION} already installed"
  else
    download_verified "${HELM_DIFF_URL}" "${HELM_DIFF_SHA256}" "${MB_DOWNLOAD_DIR}/helm-diff-${HELM_DIFF_VERSION}-linux-amd64.tgz"
    run rm -rf "${plugins_dir}/diff"
    run mkdir -p "${plugins_dir}"
    run tar -xzf "${MB_DOWNLOAD_DIR}/helm-diff-${HELM_DIFF_VERSION}-linux-amd64.tgz" -C "${plugins_dir}"
  fi
}

# ---------------------------------------------------------------------------
# Phase 3: cert-manager
# ---------------------------------------------------------------------------
phase_cert_manager() {
  log "[3/14] cert-manager ${CERT_MANAGER_VERSION} (pinned release manifest)"
  info "note: ${CERT_MANAGER_VERSION} is upstream's pin; it is end-of-life and officially supports Kubernetes <= 1.32 (we run K3s v1.36). Tracked in README.md."
  download_verified "${CERT_MANAGER_URL}" "${CERT_MANAGER_SHA256}" "${MB_DOWNLOAD_DIR}/cert-manager-${CERT_MANAGER_VERSION}.yaml"
  run kubectl apply -f "${MB_DOWNLOAD_DIR}/cert-manager-${CERT_MANAGER_VERSION}.yaml"
  local d
  for d in cert-manager cert-manager-cainjector cert-manager-webhook; do
    run kubectl -n cert-manager rollout status "deploy/${d}" --timeout=180s
  done
}

# ---------------------------------------------------------------------------
# Phase 4: CA Secret + ClusterIssuer (ADR 0004)
# ---------------------------------------------------------------------------
phase_issuer() {
  log "[4/14] ClusterIssuer ${CLUSTER_ISSUER} (kind CA) from ${APPLIANCE_CA_DIR}"
  require_ca_files
  # Trade-off, stated plainly: a cert-manager CA issuer needs the CA *private
  # key* inside the cluster (Secret in namespace cert-manager). Anyone with
  # cluster-admin on this single-node demo cluster can read it. Acceptable for
  # a demo whose CA is generated per install and trusted only by this
  # appliance; NOT for production (there, use an intermediate or an external
  # issuer). ADR 0004.
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: kubectl -n cert-manager create secret tls %s --cert=%s --key=%s --dry-run=client -o yaml | kubectl apply -f -\n' \
      "${CA_SECRET_NAME}" "${CA_CRT}" "${CA_KEY}"
  else
    kubectl -n cert-manager create secret tls "${CA_SECRET_NAME}" \
      --cert="${CA_CRT}" --key="${CA_KEY}" --dry-run=client -o yaml | kubectl apply -f -
  fi
  apply_manifest "ClusterIssuer ${CLUSTER_ISSUER}" <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${CLUSTER_ISSUER}
spec:
  ca:
    secretName: ${CA_SECRET_NAME}
YAML
  run kubectl wait --for=condition=Ready "clusterissuer/${CLUSTER_ISSUER}" --timeout=120s
}

# ---------------------------------------------------------------------------
# Phase 5: master password
# ---------------------------------------------------------------------------
generate_password() {
  # 32 characters from [A-Za-z0-9] (~190 bits). Alphanumeric only so it is
  # safe in YAML, shell and Helm templates. Loop guards against short output.
  local pw=""
  while [[ "${#pw}" -lt 32 ]]; do
    pw="${pw}$(head -c 96 /dev/urandom | base64 | LC_ALL=C tr -dc 'A-Za-z0-9')"
  done
  printf '%s' "${pw:0:32}"
}

phase_password() {
  log "[5/14] Master password: ${MB_MASTER_PASSWORD_FILE}"
  if [[ -s "${MB_MASTER_PASSWORD_FILE}" ]]; then
    info "reusing existing master password (not shown)"
    if [[ "${DRY_RUN}" -eq 0 ]]; then chmod 600 "${MB_MASTER_PASSWORD_FILE}"; fi
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: generate 32-char random password -> %s (dir 0700, file 0600, root-only)\n' "${MB_MASTER_PASSWORD_FILE}"
    return 0
  fi
  local dir pw
  dir="$(dirname "${MB_MASTER_PASSWORD_FILE}")"
  (umask 077 && mkdir -p "${dir}")
  chmod 700 "${dir}"
  pw="$(generate_password)"
  (umask 077 && printf '%s\n' "${pw}" >"${MB_MASTER_PASSWORD_FILE}")
  chmod 600 "${MB_MASTER_PASSWORD_FILE}"
  info "generated new master password (not shown). Every Mijn Bureau secret derives from it; back it up with the VM."
}

# ---------------------------------------------------------------------------
# Phase 6: source at pinned revision
# ---------------------------------------------------------------------------
phase_source() {
  log "[6/14] mijn-bureau-infra at ${MB_REV}"
  # Why git and not a tarball: the commit hash is content-addressed, so
  # `git rev-parse HEAD == MB_REV` after checkout verifies every file without
  # a second checksum, and it works identically from the primary
  # (code.overheid.nl) and the mirror (GitHub). GitHub's on-the-fly tarballs are
  # not guaranteed byte-stable. The tarball SHA-256 is recorded in README.md
  # for reference only.
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: git init %s; git fetch --depth 1 <%s> %s (fallback: full fetch); git checkout %s; verify HEAD == %s\n' \
      "${MB_SRC_DIR}" "${MB_REPO_URLS[0]}|${MB_REPO_URLS[1]}" "${MB_REV}" "${MB_REV}" "${MB_REV}"
    return 0
  fi
  if [[ -d "${MB_SRC_DIR}/.git" ]] && [[ "$(git -C "${MB_SRC_DIR}" rev-parse HEAD 2>/dev/null)" == "${MB_REV}" ]]; then
    info "already at ${MB_REV:0:12} in ${MB_SRC_DIR}"
    return 0
  fi
  mkdir -p "${MB_SRC_DIR}"
  [[ -d "${MB_SRC_DIR}/.git" ]] || git -C "${MB_SRC_DIR}" init -q
  local url ok=0
  for url in "${MB_REPO_URLS[@]}"; do
    info "fetching ${MB_REV:0:12} from ${url}"
    git -C "${MB_SRC_DIR}" remote remove origin >/dev/null 2>&1 || true
    git -C "${MB_SRC_DIR}" remote add origin "${url}"
    if git -C "${MB_SRC_DIR}" fetch -q --depth 1 origin "${MB_REV}" 2>/dev/null \
      || git -C "${MB_SRC_DIR}" fetch -q origin 2>/dev/null; then
      if git -C "${MB_SRC_DIR}" cat-file -e "${MB_REV}^{commit}" 2>/dev/null; then
        ok=1
        break
      fi
    fi
    warn "could not obtain ${MB_REV:0:12} from ${url}, trying next"
  done
  [[ "${ok}" -eq 1 ]] || die "could not fetch mijn-bureau-infra ${MB_REV} from any configured URL"
  git -C "${MB_SRC_DIR}" checkout -q --detach "${MB_REV}"
  [[ "$(git -C "${MB_SRC_DIR}" rev-parse HEAD)" == "${MB_REV}" ]] || die "checkout is not at ${MB_REV}"
  info "verified: HEAD == ${MB_REV}"
}

# ---------------------------------------------------------------------------
# Phase 7: demo environment values (upstream 01-deploy.sh, adapted)
# ---------------------------------------------------------------------------
phase_values() {
  log "[7/14] Demo values: ${MB_SRC_DIR}/helmfile/environments/demo/mijnbureau.yaml.gotmpl"
  # Differences from upstream's 01-deploy.sh heredoc, and why:
  #  - global.domain: our base domain (ADR 0004).
  #  - cert-manager.io/cluster-issuer: dawo-appliance-ca instead of
  #    letsencrypt-prod (ADR 0004). global.tls.selfSigned stays false.
  #  - application.<app>.enabled: true is stated explicitly for the nine apps
  #    upstream gives a namespace. At rev b2ae545 the defaults for grist and
  #    nextcloud are `enabled: false` (changed upstream on 2026-07-22, after the
  #    single-VPS scripts were written on 2026-06-15), so upstream's own demo
  #    values would silently skip them and 03-restart-oidc-apps.sh would fail.
  #  Everything else (resource preset none, subnets, ollama/clamav/openproject
  #  disabled, OIDC endpoints) is upstream's, verbatim.
  write_file "${MB_SRC_DIR}/helmfile/environments/demo/mijnbureau.yaml.gotmpl" 0644 <<YAML
---
# Written by dawo-appliance apps/mijn-bureau/deploy.sh (phase 7). Do not edit
# by hand; re-run the driver. Based on upstream scripts/single-vps-deploy/
# 01-deploy.sh at ${MB_REV:0:12}, adapted per ADR 0004.
global:
  domain: "${MB_DOMAIN}"
  resourcesPreset: "none"
  resourcesPresetPerApp:
    collabora: "none"
    elementweb: "none"
    keycloak: "none"
    ollama: "none"
    synapse: "none"
    grist: "none"
    livekit: "none"
    meet: { backend: "none", frontend: "none" }
    nextcloud: "none"
    docs: { backend: "none", frontend: "none", celery: "none", yProvider: "none", docspec: "none" }
    drive: { backend: "none", frontend: "none" }
    conversations: { backend: "none", frontend: "none" }
    bureaublad: { backend: "none", frontend: "none" }
  tls:
    enabled: true
    selfSigned: false

cluster:
  routingMode: ingress
  ingress:
    type: traefik
    annotations:
      cert-manager.io/cluster-issuer: ${CLUSTER_ISSUER}
  networking:
    podSubnet:
      - "10.42.0.0/16"
    serviceSubnet:
      - "10.43.0.0/16"

application:
  ollama:
    enabled: false
  # Antivirus and project management are disabled as in upstream's single-VPS
  # setup. OpenProject additionally needs security.openproject and
  # tls.openproject blocks (see upstream's guide).
  clamav:
    enabled: false
  openproject:
    enabled: false
  keycloak:    { enabled: true, namespace: mb-keycloak }
  grist:       { enabled: true, namespace: mb-grist }
  element:     { enabled: true, namespace: mb-element }
  collabora:   { enabled: true, namespace: mb-collabora }
  nextcloud:   { enabled: true, namespace: mb-nextcloud }
  livekit:     { enabled: true, namespace: mb-livekit }
  meet:        { enabled: true, namespace: mb-meet }
  docs:        { enabled: true, namespace: mb-docs }
  bureaublad:  { enabled: true, namespace: mb-bureaublad }

authentication:
  oidc:
    issuer: "https://id.${MB_DOMAIN}/realms/mijnbureau"
    authorization_endpoint: "https://id.${MB_DOMAIN}/realms/mijnbureau/protocol/openid-connect/auth"
    token_endpoint: "https://id.${MB_DOMAIN}/realms/mijnbureau/protocol/openid-connect/token"
    introspection_endpoint: "https://id.${MB_DOMAIN}/realms/mijnbureau/protocol/openid-connect/token/introspect"
    userinfo_endpoint: "https://id.${MB_DOMAIN}/realms/mijnbureau/protocol/openid-connect/userinfo"
    end_session_endpoint: "https://id.${MB_DOMAIN}/realms/mijnbureau/protocol/openid-connect/logout"
    jwks_uri: "https://id.${MB_DOMAIN}/realms/mijnbureau/protocol/openid-connect/certs"
YAML
  # Upstream's 02-networking.sh and 07-session-lifetimes.sh read the domain
  # from here when run by hand; keep that working.
  write_file /etc/mijnbureau/domain 0644 <<EOF
${MB_DOMAIN}
EOF
}

# ---------------------------------------------------------------------------
# Phase 8: helmfile apply
# ---------------------------------------------------------------------------
phase_deploy() {
  log "[8/14] helmfile -e demo apply (10-20 minutes on first run)"
  export MIJNBUREAU_CREATE_NAMESPACES=true
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: export MIJNBUREAU_MASTER_PASSWORD=<contents of %s, never printed>\n' "${MB_MASTER_PASSWORD_FILE}"
    printf 'DRY-RUN: (cd %s && helmfile -e demo apply --skip-diff-on-install)\n' "${MB_SRC_DIR}"
    return 0
  fi
  [[ -s "${MB_MASTER_PASSWORD_FILE}" ]] || die "master password file missing: ${MB_MASTER_PASSWORD_FILE} (run --phase password)"
  [[ -f "${MB_SRC_DIR}/helmfile.yaml.gotmpl" ]] || die "source checkout missing: ${MB_SRC_DIR} (run --phase source)"
  MIJNBUREAU_MASTER_PASSWORD="$(head -n1 "${MB_MASTER_PASSWORD_FILE}")"
  export MIJNBUREAU_MASTER_PASSWORD
  (cd "${MB_SRC_DIR}" && "${MB_BIN_DIR}/helmfile" -e demo apply --skip-diff-on-install)
  unset MIJNBUREAU_MASTER_PASSWORD
}

# ---------------------------------------------------------------------------
# Phase 9 / 12 / 13: upstream scripts from the pinned checkout
# ---------------------------------------------------------------------------
run_upstream() { # run_upstream SCRIPT [ARGS...]
  local script="$1"; shift
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: bash %s/%s %s   (from pinned checkout %s)\n' "${UPSTREAM_SCRIPTS}" "${script}" "$*" "${MB_REV:0:12}"
    return 0
  fi
  [[ -f "${UPSTREAM_SCRIPTS}/${script}" ]] || die "upstream script missing: ${UPSTREAM_SCRIPTS}/${script} (run --phase source)"
  bash "${UPSTREAM_SCRIPTS}/${script}" "$@"
}

phase_networking() {
  log "[9/14] Single-node networking workarounds (upstream 02-networking.sh)"
  # CoreDNS rewrites *.${MB_DOMAIN} to the in-cluster Traefik service, so pods
  # never depend on the libvirt dnsmasq or NAT hairpin (ADR 0004). Also the
  # 8443 egress policies and LiveKit node_ip. Idempotent upstream.
  run_upstream 02-networking.sh "${MB_DOMAIN}"
}

phase_oidc_restart() {
  log "[12/14] Nextcloud SSRF/trusted_proxies + restart OIDC apps (upstream 03-restart-oidc-apps.sh)"
  run_upstream 03-restart-oidc-apps.sh
}

phase_post_fixes() {
  log "[13/14] Post-deploy fixes (upstream 04, 05, 06)"
  run_upstream 04-nextcloud-office.sh
  run_upstream 05-docs.sh
  run_upstream 06-grist.sh
}

# ---------------------------------------------------------------------------
# Phase 10: wait for certificates (upstream install.sh wait_for_certs)
# ---------------------------------------------------------------------------
phase_wait_certs() {
  log "[10/14] Waiting for all cert-manager Certificates (timeout ${MB_CERT_TIMEOUT}s)"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    # shellcheck disable=SC2016  # literal, meant to print as the command a real run would use
    printf 'DRY-RUN: poll `kubectl get certificate -A` until all Ready and the count is stable over two polls; then check issuerRef == %s\n' "${CLUSTER_ISSUER}"
    return 0
  fi
  sleep 30 # let cert-manager create Certificate objects for every Ingress
  local prev=-1 stable=0 total ready waited=30
  while :; do
    total=$(kubectl get certificate -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    ready=$(kubectl get certificate -A --no-headers 2>/dev/null | awk '$3=="True"' | wc -l | tr -d ' ')
    info "certificates ready: ${ready}/${total}"
    if [[ "${total}" -gt 0 && "${total}" -eq "${ready}" ]]; then
      if [[ "${total}" -eq "${prev}" ]]; then
        stable=$((stable + 1))
        [[ "${stable}" -ge 2 ]] && break
      else
        stable=0
      fi
    else
      stable=0
    fi
    prev="${total}"
    [[ "${waited}" -lt "${MB_CERT_TIMEOUT}" ]] || die "certificates not all Ready after ${MB_CERT_TIMEOUT}s; inspect: kubectl get certificate -A; kubectl describe clusterissuer ${CLUSTER_ISSUER}"
    sleep 15
    waited=$((waited + 15))
  done
  info "all ${total} certificates ready"
  local foreign
  foreign="$(kubectl get certificate -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.spec.issuerRef.name}{"\n"}{end}' \
    | awk -v want="${CLUSTER_ISSUER}" '$2!=want{print $1" ("$2")"}')"
  if [[ -n "${foreign}" ]]; then
    warn "certificates not issued by ${CLUSTER_ISSUER}:"
    printf '%s\n' "${foreign}" | sed 's/^/      /' >&2
  else
    info "every certificate references issuer ${CLUSTER_ISSUER}"
  fi
}

# ---------------------------------------------------------------------------
# Phase 11: in-cluster trust of the appliance CA (ADR 0004)
# ---------------------------------------------------------------------------
# Pattern: upstream's 03-restart-oidc-apps.sh patches, then rollout-restarts.
# We add a ConfigMap with ca.crt in each mb-* namespace, mount it into the
# server-side OIDC clients upstream restarts, and announce it per runtime via
# environment variables. Changing the pod template triggers a rollout; the
# strategic-merge patch is idempotent (kubectl reports "no change" on re-run).
# Verification is never disabled.
ensure_ca_configmap() { # ensure_ca_configmap NAMESPACE
  local ns="$1"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: kubectl -n %s create configmap %s --from-file=ca.crt=%s --dry-run=client -o yaml | kubectl apply -f -\n' "${ns}" "${CA_CONFIGMAP_NAME}" "${CA_CRT}"
    return 0
  fi
  kubectl -n "${ns}" create configmap "${CA_CONFIGMAP_NAME}" --from-file="ca.crt=${CA_CRT}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# patch_deploy_trust NAMESPACE DEPLOYMENT ENVVAR...
# Mounts the CA ConfigMap at ${CA_MOUNT_PATH}/ca.crt in every container of the
# deployment and sets each ENVVAR to that path. Container names are read from
# the live object because they differ per chart (e.g. docs uses a template name,
# synapse is an external chart).
patch_deploy_trust() {
  local ns="$1" deploy="$2"; shift 2
  local envs=("$@") names name env_json="" containers_json="" patch e
  for e in "${envs[@]}"; do
    env_json="${env_json:+${env_json},}{\"name\":\"${e}\",\"value\":\"${CA_MOUNT_PATH}/ca.crt\"}"
  done
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: kubectl -n %s patch deploy/%s --type strategic: mount ConfigMap %s at %s in every container; env %s=%s/ca.crt\n' \
      "${ns}" "${deploy}" "${CA_CONFIGMAP_NAME}" "${CA_MOUNT_PATH}" "$(IFS=,; printf '%s' "${envs[*]}")" "${CA_MOUNT_PATH}"
    return 0
  fi
  if ! kubectl -n "${ns}" get "deploy/${deploy}" >/dev/null 2>&1; then
    warn "deploy/${deploy} not found in ${ns}; skipping CA trust patch"
    return 0
  fi
  names="$(kubectl -n "${ns}" get "deploy/${deploy}" -o jsonpath='{.spec.template.spec.containers[*].name}')"
  for name in ${names}; do
    containers_json="${containers_json:+${containers_json},}{\"name\":\"${name}\",\"volumeMounts\":[{\"name\":\"${CA_CONFIGMAP_NAME}\",\"mountPath\":\"${CA_MOUNT_PATH}\",\"readOnly\":true}],\"env\":[${env_json}]}"
  done
  patch="{\"spec\":{\"template\":{\"spec\":{\"volumes\":[{\"name\":\"${CA_CONFIGMAP_NAME}\",\"configMap\":{\"name\":\"${CA_CONFIGMAP_NAME}\"}}],\"containers\":[${containers_json}]}}}}"
  kubectl -n "${ns}" patch "deploy/${deploy}" --type strategic -p "${patch}"
}

phase_trust() {
  log "[11/14] In-cluster trust of the appliance CA (ADR 0004)"
  require_ca_files
  local ns
  for ns in "${MB_NAMESPACES[@]}"; do ensure_ca_configmap "${ns}"; done

  # Derived directly from the set upstream restarts in 03-restart-oidc-apps.sh:
  patch_deploy_trust mb-grist grist NODE_EXTRA_CA_CERTS                          # Node.js
  patch_deploy_trust mb-docs docs-backend SSL_CERT_FILE REQUESTS_CA_BUNDLE       # Python/Django (requests, httpx)
  patch_deploy_trust mb-meet meet-backend SSL_CERT_FILE REQUESTS_CA_BUNDLE       # Python/Django
  patch_deploy_trust mb-element synapse SSL_CERT_FILE REQUESTS_CA_BUNDLE         # Python/Twisted (OpenSSL default paths)

  # Nextcloud (PHP/curl): import into its own certificate store, persisted in
  # the data volume. Idempotent: same file name replaces the same entry.
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY-RUN: kubectl -n mb-nextcloud rollout status deploy/nextcloud --timeout=600s\n'
    printf 'DRY-RUN: kubectl -n mb-nextcloud exec -i deploy/nextcloud -- sh -c "cat > /tmp/dawo-appliance-ca.crt" < %s\n' "${CA_CRT}"
    printf 'DRY-RUN: kubectl -n mb-nextcloud exec deploy/nextcloud -- php occ security:certificates:import /tmp/dawo-appliance-ca.crt\n'
  else
    if kubectl -n mb-nextcloud get deploy/nextcloud >/dev/null 2>&1; then
      kubectl -n mb-nextcloud rollout status deploy/nextcloud --timeout=600s
      kubectl -n mb-nextcloud exec -i deploy/nextcloud -- sh -c 'cat > /tmp/dawo-appliance-ca.crt' <"${CA_CRT}"
      kubectl -n mb-nextcloud exec deploy/nextcloud -- php occ security:certificates:import /tmp/dawo-appliance-ca.crt
    else
      warn "deploy/nextcloud not found; skipping occ security:certificates:import"
    fi
  fi

  local d
  for d in mb-grist/grist mb-docs/docs-backend mb-meet/meet-backend mb-element/synapse; do
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      printf 'DRY-RUN: kubectl -n %s rollout status deploy/%s --timeout=600s\n' "${d%/*}" "${d#*/}"
    elif kubectl -n "${d%/*}" get "deploy/${d#*/}" >/dev/null 2>&1; then
      kubectl -n "${d%/*}" rollout status "deploy/${d#*/}" --timeout=600s
    fi
  done

  # Not yet implemented; each needs per-app verification on a real cluster.
  # Exact knobs, from the pinned charts (ADR 0004):
  todo "Keycloak back-channel calls: chart value trustedCertsExistingSecret (mounted, KC_TRUSTSTORE_PATHS) -> Secret with ca.crt in mb-keycloak via helmfile/apps/keycloak values"
  todo "Collabora WOPI to https://nextcloud.${MB_DOMAIN}: append --o:ssl.ca_file_path=${CA_MOUNT_PATH}/ca.crt to collabora.extra_params (helmfile/apps/collabora/values-collabora.yaml.gotmpl) plus extraVolumes/extraVolumeMounts"
  todo "Docs celery worker / y-provider (deploy/docs-celery-worker, deploy/docs-y-provider) and Bureaublad backend (deploy/bureaublad-backend): same env pattern once their runtimes' TLS calls are confirmed"
  todo "Move the env/volume additions from kubectl patches into chart values (extraEnvVars, extraVolumes, extraVolumeMounts) so a re-run of helmfile apply cannot revert them"
}

# ---------------------------------------------------------------------------
# Phase 14: Keycloak session lifetimes (upstream 07-session-lifetimes.sh)
# ---------------------------------------------------------------------------
# Reimplemented (not run from the checkout) because upstream's version calls
# https://id.DOMAIN without --cacert and relies on the guest resolver; we pin
# the CA and resolve the name to the node so the step does not depend on the
# host-side DNS/trust wiring of Slice 4.
phase_sessions() {
  log "[14/14] Keycloak session lifetimes on realm mijnbureau (upstream step 7)"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    # shellcheck disable=SC2016  # literal, meant to print as the command a real run would use
    printf 'DRY-RUN: KC_PASS=$(kubectl -n mb-keycloak get secret keycloak-keycloak -o jsonpath={.data.admin-password} | base64 -d)\n'
    printf 'DRY-RUN: curl --cacert %s --resolve id.%s:443:<node InternalIP> https://id.%s/realms/master/protocol/openid-connect/token (admin-cli) -> token\n' "${CA_CRT}" "${MB_DOMAIN}" "${MB_DOMAIN}"
    printf 'DRY-RUN: curl -X PUT https://id.%s/admin/realms/mijnbureau {"accessTokenLifespan":1800,"ssoSessionIdleTimeout":604800,"ssoSessionMaxLifespan":2592000,"rememberMe":true}\n' "${MB_DOMAIN}"
    return 0
  fi
  require_ca_files
  local node_ip kc_pass token resolve
  node_ip="$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' \
    | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
  [[ -n "${node_ip}" ]] || die "could not determine node InternalIP"
  resolve="id.${MB_DOMAIN}:443:${node_ip}"
  kc_pass="$(kubectl -n mb-keycloak get secret keycloak-keycloak -o jsonpath='{.data.admin-password}' | base64 -d)"
  # kc_pass and the resulting bearer token never touch argv (visible to any
  # local user via `ps`/`/proc/<pid>/cmdline`): the password goes to curl via
  # --data-urlencode's "@-" stdin form, the token via a -K config on stdin.
  token="$(curl -fsS --cacert "${CA_CRT}" --resolve "${resolve}" \
    "https://id.${MB_DOMAIN}/realms/master/protocol/openid-connect/token" \
    -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode "password@-" \
    <<<"${kc_pass}" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')"
  [[ "${token}" != *$'\n'* && "${token}" != *'"'* ]] || die "unexpected characters in Keycloak access token"
  curl -fsS --cacert "${CA_CRT}" --resolve "${resolve}" -X PUT "https://id.${MB_DOMAIN}/admin/realms/mijnbureau" \
    -K - -H "Content-Type: application/json" \
    -d '{"accessTokenLifespan":1800,"ssoSessionIdleTimeout":604800,"ssoSessionMaxLifespan":2592000,"rememberMe":true}' \
    <<<"header = \"Authorization: Bearer ${token}\""
  info "realm updated: 30-minute access token, 7-day idle, 30-day max session, remember-me"
}

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: deploy.sh [--dry-run] [--phase <n|name>] [--list-phases] [--print-pins] [-h]

Deploys Mijn Bureau (mijn-bureau-infra ${MB_REV:0:12}) onto the K3s cluster in
this guest, per ADR 0004 (base domain ${MB_DOMAIN_DEFAULT}, ClusterIssuer ${CLUSTER_ISSUER}).

  --dry-run        print every action; create, download and change nothing
  --phase <n|name> run a single phase (see --list-phases)
  --list-phases    list phases and exit
  --print-pins     print the pinned versions/checksums as key=value and exit

Environment: APPLIANCE_CA_DIR (${APPLIANCE_CA_DIR}: ca.crt, ca.key), MB_DOMAIN,
MB_STATE_DIR (${MB_STATE_DIR}), MB_MASTER_PASSWORD_FILE, MB_SRC_DIR, MB_BIN_DIR,
MB_DOWNLOAD_DIR, MB_CERT_TIMEOUT, KUBECONFIG (${KUBECONFIG}).
EOF
}

list_phases() {
  local p
  for p in "${PHASES[@]}"; do
    printf '%3s  %-13s %s\n' "${p%%:*}" "$(cut -d: -f2 <<<"${p}")" "$(cut -d: -f3- <<<"${p}")"
  done
}

print_pins() {
  cat <<EOF
mijn_bureau_rev=${MB_REV}
mijn_bureau_repo_url=${MB_REPO_URLS[0]}
mijn_bureau_repo_mirror=${MB_REPO_URLS[1]}
base_domain=${MB_DOMAIN_DEFAULT}
cluster_issuer=${CLUSTER_ISSUER}
dashboard_url=https://bureaublad.${MB_DOMAIN_DEFAULT}
helmfile_version=${HELMFILE_VERSION}
helmfile_url=${HELMFILE_URL}
helmfile_sha256=${HELMFILE_SHA256}
helm_version=${HELM_VERSION}
helm_url=${HELM_URL}
helm_sha256=${HELM_SHA256}
helm_diff_version=${HELM_DIFF_VERSION}
helm_diff_url=${HELM_DIFF_URL}
helm_diff_sha256=${HELM_DIFF_SHA256}
cert_manager_version=${CERT_MANAGER_VERSION}
cert_manager_url=${CERT_MANAGER_URL}
cert_manager_sha256=${CERT_MANAGER_SHA256}
EOF
}

run_phase() { # run_phase NUMBER
  # Re-validated here (not just in phase_preflight) because --phase lets any
  # single phase run standalone, and MB_DOMAIN is spliced unescaped into a
  # YAML heredoc in phase_values (a bogus value there is a YAML-injection risk
  # into the Helmfile values, not just a broken deploy).
  validate_domain
  case "$1" in
    1) phase_preflight ;;
    2) phase_tools ;;
    3) phase_cert_manager ;;
    4) phase_issuer ;;
    5) phase_password ;;
    6) phase_source ;;
    7) phase_values ;;
    8) phase_deploy ;;
    9) phase_networking ;;
    10) phase_wait_certs ;;
    11) phase_trust ;;
    12) phase_oidc_restart ;;
    13) phase_post_fixes ;;
    14) phase_sessions ;;
    *) die "internal: unknown phase number $1" ;;
  esac
}

resolve_phase() { # resolve_phase <n|name> -> number on stdout
  local p
  for p in "${PHASES[@]}"; do
    if [[ "${p%%:*}" == "$1" || "$(cut -d: -f2 <<<"${p}")" == "$1" ]]; then
      printf '%s' "${p%%:*}"
      return 0
    fi
  done
  return 1
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --phase) [[ $# -ge 2 ]] || die "--phase needs an argument"; PHASE="$2"; shift ;;
      --phase=*) PHASE="${1#--phase=}" ;;
      --list-phases) list_phases; exit 0 ;;
      --print-pins) print_pins; exit 0 ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; die "unknown argument: $1" ;;
    esac
    shift
  done

  log "dawo-appliance Mijn Bureau driver: rev ${MB_REV:0:12}, domain ${MB_DOMAIN}, issuer ${CLUSTER_ISSUER}$([[ "${DRY_RUN}" -eq 1 ]] && printf ' [DRY-RUN]')"

  if [[ -n "${PHASE}" ]]; then
    local n
    n="$(resolve_phase "${PHASE}")" || die "unknown phase: ${PHASE} (see --list-phases)"
    run_phase "${n}"
  else
    local p
    for p in "${PHASES[@]}"; do run_phase "${p%%:*}"; done
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN complete. NOTHING WAS CHANGED."
  elif [[ -z "${PHASE}" ]]; then
    log "Done. Mijn Bureau should be reachable at https://bureaublad.${MB_DOMAIN} (health check: Slice 7)."
  fi
}

main "$@"
