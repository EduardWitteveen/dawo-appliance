#!/usr/bin/env bash
#
# install-k3s.sh — pinned, verified single-node K3s installer for the Ubuntu
# 24.04 guest of dawo-appliance (Slice 5).
#
# Upstream (mijn-bureau-infra scripts/single-vps-deploy/01-deploy.sh, line 21)
# runs `curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode
# 644" sh -`, i.e. an unpinned channel lookup. This script instead:
#
#   1. downloads the `k3s` binary and `install.sh` of ONE pinned release tag
#      (or takes them from K3S_OFFLINE_DIR),
#   2. verifies BOTH against SHA-256 pins recorded in
#      manifest/appliance-manifest.json (kubernetes.version),
#   3. places the binary at ${K3S_BIN_DIR}/k3s (0755),
#   4. runs the pinned install.sh with INSTALL_K3S_SKIP_DOWNLOAD=true so the
#      installer fetches nothing, keeping upstream's server flags
#      (--write-kubeconfig-mode 644, bundled Traefik enabled) plus a TLS SAN
#      for the appliance host (ADR 0004),
#   5. waits until the node is Ready and prints the versions.
#
# Self-contained: no repository checkout is needed inside the guest. The guest
# cloud-init embeds this file and calls it from `runcmd` (see README.md).
# Idempotent: exits 0 without changes when the pinned binary is installed and
# the k3s service is active.
#
# Environment (all optional; defaults are the manifest pins):
#   K3S_VERSION             release tag, e.g. v1.36.4+k3s1
#   K3S_BINARY_SHA256       SHA-256 of the amd64 `k3s` binary
#   K3S_INSTALL_SH_SHA256   SHA-256 of install.sh at that tag
#   K3S_DOWNLOAD_BASE       release asset base URL (ends with /)
#   K3S_INSTALL_SH_URL      URL of install.sh (default: raw GitHub at the tag)
#   K3S_TLS_SAN             extra API-server SAN (default mb.dawo.internal)
#   K3S_EXTRA_EXEC          extra `k3s server` flags appended verbatim
#   K3S_BIN_DIR             install directory (default /usr/local/bin)
#   K3S_OFFLINE_DIR         directory with pre-downloaded `k3s` + `install.sh`;
#                           no network is used
#   K3S_NODE_READY_TIMEOUT  seconds to wait for the node (default 300)
#   K3S_DRY_RUN=1           download/copy + verify only; print the install
#                           command and exit 0 before touching the system
#
# Arguments: --print-pins (print effective pins and exit), --help.
#
# Exit codes: 0 ok / already installed; 1 usage or environment error;
# 2 download or missing file; 3 checksum mismatch; 4 install or node not Ready.
#
# Experimental and unofficial. Not an official DAWO / Mijn Bureau / BZK tool.

set -euo pipefail

# --- pins (source of truth: manifest/appliance-manifest.json) ---------------
# tests/test-k3s-install.sh asserts these equal the manifest values.
readonly DEFAULT_K3S_VERSION="v1.36.4+k3s1"
readonly DEFAULT_K3S_BINARY_SHA256="835873f37245fc615f547a2fe2af9402a347875f13fa64a1f136de644955ea3f"
readonly DEFAULT_K3S_INSTALL_SH_SHA256="46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad"
readonly DEFAULT_K3S_DOWNLOAD_BASE="https://github.com/k3s-io/k3s/releases/download/v1.36.4+k3s1/"

# Upstream 01-deploy.sh line 21 uses exactly "--write-kubeconfig-mode 644"
# (manifest kubernetes.version.install_script.env.INSTALL_K3S_EXEC). Traefik
# stays enabled: 02-networking.sh rewrites *.DOMAIN to traefik.kube-system and
# allows egress to Traefik on 8443.
readonly UPSTREAM_K3S_EXEC="--write-kubeconfig-mode 644"
readonly DEFAULT_K3S_TLS_SAN="mb.dawo.internal"

# --- effective settings ------------------------------------------------------
K3S_VERSION="${K3S_VERSION:-${DEFAULT_K3S_VERSION}}"
K3S_BINARY_SHA256="${K3S_BINARY_SHA256:-${DEFAULT_K3S_BINARY_SHA256}}"
K3S_INSTALL_SH_SHA256="${K3S_INSTALL_SH_SHA256:-${DEFAULT_K3S_INSTALL_SH_SHA256}}"
K3S_DOWNLOAD_BASE="${K3S_DOWNLOAD_BASE:-${DEFAULT_K3S_DOWNLOAD_BASE}}"
K3S_INSTALL_SH_URL="${K3S_INSTALL_SH_URL:-https://raw.githubusercontent.com/k3s-io/k3s/${K3S_VERSION//+/%2B}/install.sh}"
K3S_TLS_SAN="${K3S_TLS_SAN:-${DEFAULT_K3S_TLS_SAN}}"
K3S_EXTRA_EXEC="${K3S_EXTRA_EXEC:-}"
K3S_BIN_DIR="${K3S_BIN_DIR:-/usr/local/bin}"
K3S_OFFLINE_DIR="${K3S_OFFLINE_DIR:-}"
K3S_NODE_READY_TIMEOUT="${K3S_NODE_READY_TIMEOUT:-300}"
K3S_DRY_RUN="${K3S_DRY_RUN:-0}"

K3S_EXEC="${UPSTREAM_K3S_EXEC} --tls-san ${K3S_TLS_SAN}"
[[ -n "${K3S_EXTRA_EXEC}" ]] && K3S_EXEC="${K3S_EXEC} ${K3S_EXTRA_EXEC}"

KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"

# --- logging -----------------------------------------------------------------
log() { printf '[install-k3s] %s\n' "$*"; }
err() { printf '[install-k3s] ERROR: %s\n' "$*" >&2; }
die() {
  local code="$1"
  shift
  err "$@"
  exit "${code}"
}

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<EOF
Usage: install-k3s.sh [--print-pins | --help]
See the header comment for the environment variables.
EOF
}

print_pins() {
  cat <<EOF
K3S_VERSION=${K3S_VERSION}
K3S_BINARY_SHA256=${K3S_BINARY_SHA256}
K3S_INSTALL_SH_SHA256=${K3S_INSTALL_SH_SHA256}
K3S_DOWNLOAD_BASE=${K3S_DOWNLOAD_BASE}
K3S_INSTALL_SH_URL=${K3S_INSTALL_SH_URL}
K3S_EXEC=${K3S_EXEC}
EOF
}

case "${1:-}" in
  "") ;;
  --print-pins)
    print_pins
    exit 0
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    die 1 "unknown argument: $1"
    ;;
esac

# --- helpers -----------------------------------------------------------------
sha256_of() { sha256sum "$1" | awk '{print $1}'; }

# verify_sha256 <file> <expected> <label>: fail hard on mismatch (exit 3).
verify_sha256() {
  local file="$1" expected="$2" label="$3" actual
  actual="$(sha256_of "${file}")"
  if [[ "${actual}" != "${expected}" ]]; then
    err "SHA-256 mismatch for ${label} (${file})"
    err "  expected: ${expected}"
    err "  actual:   ${actual}"
    err "Refusing to install. Check the pin in manifest/appliance-manifest.json or the download."
    exit 3
  fi
  log "verified ${label}: sha256 ${actual:0:16}... OK"
}

# fetch <url> <dest>: curl with retries; no network when K3S_OFFLINE_DIR is set.
fetch() {
  local url="$1" dest="$2"
  log "downloading ${url}"
  curl --fail --silent --show-error --location \
    --connect-timeout 20 --max-time 900 \
    --retry 5 --retry-delay 3 --retry-all-errors \
    --output "${dest}" "${url}" \
    || die 2 "download failed: ${url}"
}

# acquire <name> <url> <dest>: from the offline dir or the network.
acquire() {
  local name="$1" url="$2" dest="$3"
  if [[ -n "${K3S_OFFLINE_DIR}" ]]; then
    [[ -f "${K3S_OFFLINE_DIR}/${name}" ]] \
      || die 2 "K3S_OFFLINE_DIR is set but ${K3S_OFFLINE_DIR}/${name} is missing"
    log "using offline copy ${K3S_OFFLINE_DIR}/${name}"
    cp -f "${K3S_OFFLINE_DIR}/${name}" "${dest}"
  else
    fetch "${url}" "${dest}"
  fi
}

k3s_service_active() { command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet k3s; }

# wait_node_ready: poll `k3s kubectl get node` until STATUS is Ready (exit 4 on
# timeout). The kubeconfig appears a few seconds after the service starts.
wait_node_ready() {
  local deadline now status
  deadline=$(($(date +%s) + K3S_NODE_READY_TIMEOUT))
  log "waiting up to ${K3S_NODE_READY_TIMEOUT}s for the node to be Ready"
  while :; do
    if [[ -r "${KUBECONFIG_PATH}" ]]; then
      status="$("${K3S_BIN_DIR}/k3s" kubectl get node --no-headers 2>/dev/null | awk 'NR==1{print $2}' || true)"
      if [[ "${status}" == "Ready" ]]; then
        log "node is Ready"
        return 0
      fi
    fi
    now=$(date +%s)
    if ((now >= deadline)); then
      err "node not Ready after ${K3S_NODE_READY_TIMEOUT}s (last status: ${status:-none})"
      command -v systemctl >/dev/null 2>&1 && systemctl status k3s --no-pager >&2 || true
      exit 4
    fi
    sleep 5
  done
}

print_versions() {
  log "k3s: $("${K3S_BIN_DIR}/k3s" --version | head -n1)"
  "${K3S_BIN_DIR}/k3s" kubectl version 2>/dev/null | sed 's/^/[install-k3s]   /' || true
  "${K3S_BIN_DIR}/k3s" kubectl get node -o wide 2>/dev/null | sed 's/^/[install-k3s]   /' || true
  log "kubeconfig: ${KUBECONFIG_PATH} (mode 644, server https://127.0.0.1:6443; SAN ${K3S_TLS_SAN})"
}

# --- main --------------------------------------------------------------------
log "pinned K3s ${K3S_VERSION} (dawo-appliance Slice 5; unofficial)"
log "server flags: ${K3S_EXEC}"
[[ "${K3S_DRY_RUN}" == "1" ]] && log "DRY RUN: nothing will be installed"

for tool in sha256sum awk; do
  command -v "${tool}" >/dev/null 2>&1 || die 1 "required tool missing: ${tool}"
done
if [[ -z "${K3S_OFFLINE_DIR}" ]]; then
  command -v curl >/dev/null 2>&1 || die 1 "required tool missing: curl (or set K3S_OFFLINE_DIR)"
fi

# Idempotency: the pinned binary is in place and the service runs -> done.
if [[ "${K3S_DRY_RUN}" != "1" && -x "${K3S_BIN_DIR}/k3s" ]] \
  && [[ "$(sha256_of "${K3S_BIN_DIR}/k3s")" == "${K3S_BINARY_SHA256}" ]] \
  && k3s_service_active; then
  log "pinned k3s ${K3S_VERSION} already installed at ${K3S_BIN_DIR}/k3s and service active; nothing to do"
  wait_node_ready
  print_versions
  exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/install-k3s.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

acquire k3s "${K3S_DOWNLOAD_BASE}k3s" "${tmp}/k3s"
acquire install.sh "${K3S_INSTALL_SH_URL}" "${tmp}/install.sh"

verify_sha256 "${tmp}/k3s" "${K3S_BINARY_SHA256}" "k3s binary ${K3S_VERSION}"
verify_sha256 "${tmp}/install.sh" "${K3S_INSTALL_SH_SHA256}" "install.sh ${K3S_VERSION}"

# The exact installer invocation (also what the dry run prints).
install_env=(
  "INSTALL_K3S_SKIP_DOWNLOAD=true"
  "INSTALL_K3S_VERSION=${K3S_VERSION}"
  "INSTALL_K3S_BIN_DIR=${K3S_BIN_DIR}"
  "INSTALL_K3S_SKIP_SELINUX_RPM=true"
  "INSTALL_K3S_EXEC=${K3S_EXEC}"
)

if [[ "${K3S_DRY_RUN}" == "1" ]]; then
  log "DRY RUN: would install ${tmp}/k3s -> ${K3S_BIN_DIR}/k3s (mode 0755)"
  log "DRY RUN: would run: env ${install_env[*]@Q} sh ${tmp}/install.sh"
  log "DRY RUN: would wait for node Ready (timeout ${K3S_NODE_READY_TIMEOUT}s) and print versions"
  log "DRY RUN: done, no changes made"
  exit 0
fi

[[ "${EUID}" -eq 0 ]] || die 1 "must run as root (installs to ${K3S_BIN_DIR} and manages the k3s service)"
[[ "$(uname -m)" == "x86_64" ]] || die 1 "pinned binary is amd64; this machine is $(uname -m)"

log "installing verified binary to ${K3S_BIN_DIR}/k3s"
mkdir -p "${K3S_BIN_DIR}"
install -m 0755 -o root -g root "${tmp}/k3s" "${K3S_BIN_DIR}/k3s"

log "running pinned install.sh (no download; SKIP_DOWNLOAD=true)"
env "${install_env[@]}" sh "${tmp}/install.sh" \
  || die 4 "install.sh failed"

# install.sh skips the start when it detects no file change (e.g. a re-run
# after a failed service); make sure the unit is enabled and active.
if command -v systemctl >/dev/null 2>&1 && ! systemctl is-active --quiet k3s; then
  log "k3s service not active; enabling and starting it"
  systemctl enable --now k3s || die 4 "could not start the k3s service"
fi

wait_node_ready
print_versions
log "done: K3s ${K3S_VERSION} installed and Ready"
