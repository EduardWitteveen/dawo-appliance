#!/usr/bin/env bash
# Deploys the Valtimo environment (#246) in the guest: upstream's official GZAC
# demo, gzac-docker-compose at a pinned commit, `docker compose --profile demo`,
# plus our override file (environments/valtimo/compose/override.yaml). Runs in
# the Ubuntu guest as root, one phase at a time, called by the host runner
# (hosts/appliance/live-valtimo.nix). Every phase is idempotent.
#
#   deploy.sh --phase <name>    park | docker | source | pull | up | ready
#   deploy.sh --stop            stop the containers (the other environment)
#   deploy.sh --dry-run --phase <name>   print what would run
#
# Inputs come from the environment, set by the host from the manifest:
#   VT_REPO VT_REV VT_OVERRIDE DOCKER_URL DOCKER_SHA COMPOSE_URL COMPOSE_SHA
#
# Experimental and unofficial. Not for production.
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail

DRY_RUN=0
PHASE=""
STOP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --phase) PHASE="${2:?--phase needs a name}"; shift ;;
    --stop) STOP=1 ;;
    *) echo "deploy.sh: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

STATE_DIR="${VT_STATE_DIR:-/var/lib/dawo-appliance-valtimo}"
SRC_DIR="${STATE_DIR}/gzac-docker-compose"
DOWNLOADS="${STATE_DIR}/downloads"
DOCKER_DIR="/opt/dawo-docker"
PROFILE="demo"

info() { echo "    $*"; }
log() { echo "==> $*"; }
die() { echo "deploy.sh: $*" >&2; exit 1; }
run() { # run CMD...: print it in a dry run, else run it
  if [[ "${DRY_RUN}" -eq 1 ]]; then printf 'DRY-RUN:'; printf ' %q' "$@"; echo; else "$@"; fi
}

download_verified() { # URL SHA256 DEST
  local url="$1" sha="$2" dest="$3"
  if [[ "${DRY_RUN}" -eq 1 ]]; then echo "DRY-RUN: curl -fsSL ${url} -o ${dest}; sha256 must be ${sha}"; return 0; fi
  mkdir -p "$(dirname "${dest}")"
  if [[ -f "${dest}" ]] && printf '%s  %s\n' "${sha}" "${dest}" | sha256sum -c --quiet - >/dev/null 2>&1; then
    info "already downloaded and verified: ${dest}"; return 0
  fi
  curl -fsSL --retry 3 "${url}" -o "${dest}.tmp"
  printf '%s  %s\n' "${sha}" "${dest}.tmp" | sha256sum -c --quiet - >/dev/null 2>&1 \
    || { rm -f "${dest}.tmp"; die "SHA-256 mismatch for ${url} (expected ${sha}); refusing to continue"; }
  mv -f "${dest}.tmp" "${dest}"
  info "downloaded and verified: ${dest}"
}

compose() {
  run env PATH="${DOCKER_DIR}/bin:${PATH}" DOCKER_HOST=unix:///run/dawo-docker.sock \
    docker compose --project-directory "${SRC_DIR}" -f "${SRC_DIR}/docker-compose.yaml" -f "${VT_OVERRIDE:?}" \
    --profile "${PROFILE}" "$@"
}

# One environment at a time (ADR 0008): Mijn Bureau runs on K3s in this guest.
# Stop K3s and its pods so they do not take the memory; it starts again at the
# guest's next boot (Mijn Bureau's start boots the guest).
phase_park() {
  log "park the other environment (K3s)"
  if [[ "${DRY_RUN}" -eq 1 ]]; then echo "DRY-RUN: systemctl stop k3s; /usr/local/bin/k3s-killall.sh"; return 0; fi
  if systemctl is-active --quiet k3s 2>/dev/null; then
    run systemctl stop k3s
  fi
  if [[ -x /usr/local/bin/k3s-killall.sh ]]; then
    run /usr/local/bin/k3s-killall.sh >/dev/null 2>&1 || true
  fi
  info "K3s is stopped"
}

# Docker Engine and the compose plugin, pinned static binaries, as a unit of
# our own (dawo-docker, own socket and data root) next to K3s's containerd.
phase_docker() {
  log "Docker Engine ${DOCKER_URL##*/} and compose"
  download_verified "${DOCKER_URL:?}" "${DOCKER_SHA:?}" "${DOWNLOADS}/${DOCKER_URL##*/}"
  download_verified "${COMPOSE_URL:?}" "${COMPOSE_SHA:?}" "${DOWNLOADS}/docker-compose"
  if [[ "${DRY_RUN}" -eq 1 ]]; then echo "DRY-RUN: unpack into ${DOCKER_DIR}, install dawo-docker.service, start it"; return 0; fi
  if ! cmp -s "${DOWNLOADS}/${DOCKER_URL##*/}.unpacked" <(printf '%s\n' "${DOCKER_SHA}") 2>/dev/null; then
    rm -rf "${DOCKER_DIR}/bin"; mkdir -p "${DOCKER_DIR}/bin"
    tar -xzf "${DOWNLOADS}/${DOCKER_URL##*/}" -C "${DOCKER_DIR}/bin" --strip-components=1
    printf '%s\n' "${DOCKER_SHA}" > "${DOWNLOADS}/${DOCKER_URL##*/}.unpacked"
  fi
  mkdir -p "${DOCKER_DIR}/cli-plugins"
  install -m 0755 "${DOWNLOADS}/docker-compose" "${DOCKER_DIR}/cli-plugins/docker-compose"
  mkdir -p /root/.docker && ln -sfn "${DOCKER_DIR}/cli-plugins" /root/.docker/cli-plugins
  cat > /etc/systemd/system/dawo-docker.service <<EOF
[Unit]
Description=Docker Engine for the Valtimo environment (dawo-appliance #246)
After=network-online.target
Wants=network-online.target

[Service]
Environment=PATH=${DOCKER_DIR}/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=${DOCKER_DIR}/bin/dockerd --host=unix:///run/dawo-docker.sock --data-root=${STATE_DIR}/docker --exec-root=/run/dawo-docker --pidfile=/run/dawo-docker.pid
Restart=on-failure
LimitNOFILE=1048576
Delegate=yes
KillMode=process

[Install]
WantedBy=
EOF
  systemctl daemon-reload
  systemctl start dawo-docker
  local i
  for i in $(seq 1 60); do
    "${DOCKER_DIR}/bin/docker" -H unix:///run/dawo-docker.sock info >/dev/null 2>&1 && break
    sleep 1
  done
  "${DOCKER_DIR}/bin/docker" -H unix:///run/dawo-docker.sock info >/dev/null 2>&1 || die "dockerd did not start"
  info "Docker Engine runs ($("${DOCKER_DIR}/bin/docker" -H unix:///run/dawo-docker.sock version --format '{{.Server.Version}}'))"
}

# Upstream's compose at the pinned commit; the commit hash verifies the files.
phase_source() {
  log "gzac-docker-compose at ${VT_REV:?}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then echo "DRY-RUN: git fetch --depth 1 ${VT_REPO:?} ${VT_REV}; verify HEAD"; return 0; fi
  if [[ -d "${SRC_DIR}/.git" ]] && [[ "$(git -C "${SRC_DIR}" rev-parse HEAD 2>/dev/null)" == "${VT_REV}" ]]; then
    info "already at ${VT_REV:0:12}"; return 0
  fi
  mkdir -p "${SRC_DIR}"
  [[ -d "${SRC_DIR}/.git" ]] || git -C "${SRC_DIR}" init -q
  git -C "${SRC_DIR}" remote remove origin >/dev/null 2>&1 || true
  git -C "${SRC_DIR}" remote add origin "${VT_REPO:?}"
  git -C "${SRC_DIR}" fetch -q --depth 1 origin "${VT_REV}" || git -C "${SRC_DIR}" fetch -q origin
  git -C "${SRC_DIR}" -c advice.detachedHead=false checkout -q "${VT_REV}"
  [[ "$(git -C "${SRC_DIR}" rev-parse HEAD)" == "${VT_REV}" ]] || die "gzac-docker-compose is not at ${VT_REV}"
  info "at ${VT_REV:0:12} (verified by the commit hash)"
}

phase_pull() {
  log "pull the demo images (by digest)"
  compose pull --quiet
}

phase_up() {
  log "start the demo (docker compose --profile ${PROFILE} up -d)"
  compose up -d
}

# Ready when Keycloak answers and the backend has finished its migrations and
# the demo cases (its readiness group includes the bootstrap), and the
# frontend answers. Bounded: 20 minutes.
phase_ready() {
  log "wait until Valtimo is ready"
  if [[ "${DRY_RUN}" -eq 1 ]]; then echo "DRY-RUN: wait for :8081/auth, the backend readiness and :80"; return 0; fi
  local waited=0 url ok
  until curl -fsS -o /dev/null --max-time 5 http://localhost:8081/auth/realms/valtimo; do
    [[ "${waited}" -ge 1200 ]] && die "Keycloak does not answer after ${waited}s"
    sleep 5; waited=$((waited + 5))
  done
  info "Keycloak answers (${waited}s)"
  until ok=""; for url in /management/health/readiness /api/management/health/readiness /actuator/health/readiness; do
          if curl -fsS --max-time 5 "http://localhost:8080${url}" 2>/dev/null | grep -q '"UP"'; then ok="${url}"; break; fi
        done; [[ -n "${ok}" ]]; do
    [[ "${waited}" -ge 1200 ]] && die "the backend is not ready after ${waited}s"
    sleep 5; waited=$((waited + 5))
  done
  info "backend ready at ${ok} (${waited}s)"
  until curl -fsS -o /dev/null --max-time 5 http://localhost/; do
    [[ "${waited}" -ge 1200 ]] && die "the frontend does not answer after ${waited}s"
    sleep 5; waited=$((waited + 5))
  done
  info "frontend answers (${waited}s)"
}

# The other environment starts: stop the containers (they keep their data).
do_stop() {
  log "stop the Valtimo containers"
  if [[ "${DRY_RUN}" -eq 0 ]] && ! systemctl is-active --quiet dawo-docker 2>/dev/null; then
    info "Docker Engine is not running"; return 0
  fi
  compose stop || true
  run systemctl stop dawo-docker
}

if [[ "${STOP}" -eq 1 ]]; then do_stop; exit 0; fi
case "${PHASE}" in
  park) phase_park ;;
  docker) phase_docker ;;
  source) phase_source ;;
  pull) phase_pull ;;
  up) phase_up ;;
  ready) phase_ready ;;
  *) die "unknown or missing --phase (park, docker, source, pull, up, ready)" ;;
esac
