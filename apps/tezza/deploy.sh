#!/usr/bin/env bash
# Deploys the Tezza environment (#261) in the guest: Contezza's own demo setup,
# tezza-packaging at a pinned commit (git.contezza.nl/community/tezza-packaging,
# its docker-compose.yml and resources/), the document base of it (Alfresco
# with Tezza, Share, Keycloak, LDAP; not the ZGW part, which needs more memory
# than the guest has), plus our override file
# (environments/tezza/compose/override.yaml). Runs in the Ubuntu guest as root,
# one phase at a time, called by the host runner
# (hosts/appliance/live-tezza.nix). Every phase is idempotent. Nothing of Tezza
# is in the image: everything is downloaded from Contezza when it starts.
#
#   deploy.sh --phase <name>    park | docker | source | pull | up | ready | setup
#   deploy.sh --stop            stop the containers (the other environment)
#   deploy.sh --dry-run --phase <name>   print what would run
#
# Inputs come from the environment, set by the host from the manifest:
#   TZ_REPO TZ_REV TZ_OVERRIDE DOCKER_URL DOCKER_SHA COMPOSE_URL COMPOSE_SHA
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

STATE_DIR="${TZ_STATE_DIR:-/var/lib/dawo-appliance-tezza}"
SRC_DIR="${STATE_DIR}/tezza-packaging"
DOWNLOADS="${STATE_DIR}/downloads"
DOCKER_DIR="${DAWO_DOCKER_DIR:-/opt/dawo-docker}" # overridable for tests outside the guest
# The document base of upstream's compose (its README: Tezza at :8082, the
# Admin Tools at :8084, Share at :8081). Upstream has no profiles: the
# services are named. Left out: the ZGW part (gzac, openzaak, notificaties,
# objecten, objecttypen, personen-mock; about 5 GB more) and the apps that
# Contezza's price list marks as Enterprise-only (tezza-rm, tezza-reports,
# tezza-akten).
SERVICES=(platform platform-ass platform-db platform-activemq platform-transform-core-aio
          identity identity-db openldap share app-tezza app-tezza-admin
          authorization-profiles authorization-profiles-db)
# The compose project (the directory name).
PROJECT="tezza-packaging"
DOCKER_SOCK="${DAWO_DOCKER_SOCK:-unix:///run/dawo-docker.sock}"

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
  # Two images at a time: all at once choked a slow network (see the Valtimo
  # driver). Upstream's compose file and our override; no profiles.
  run env PATH="${DOCKER_DIR}/bin:${PATH}" DOCKER_HOST="${DOCKER_SOCK}" COMPOSE_PARALLEL_LIMIT=2 \
    docker compose --project-directory "${SRC_DIR}" -f "${SRC_DIR}/docker-compose.yml" -f "${TZ_OVERRIDE:?}" "$@"
}

# One environment at a time (ADR 0008). The containers of every other compose
# project on the shared Docker Engine (dawo-docker, D43) are stopped
# explicitly: upstream's `restart: unless-stopped` (and `always`) would
# otherwise bring them back each time the engine starts, for example after
# the guest rebooted while Nextcloud Common Ground ran. Explicitly stopped
# containers stay stopped; their volumes and data stay.
park_other_compose_projects() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "DRY-RUN: docker ps: stop the running containers of every compose project but ${PROJECT}"; return 0
  fi
  "${DOCKER_DIR}/bin/docker" -H "${DOCKER_SOCK}" info >/dev/null 2>&1 || { info "Docker Engine is not running"; return 0; }
  local others
  others="$("${DOCKER_DIR}/bin/docker" -H "${DOCKER_SOCK}" ps --format '{{.ID}} {{.Label "com.docker.compose.project"}}' \
             | awk -v me="${PROJECT}" '$2 != "" && $2 != me')"
  if [[ -z "${others}" ]]; then info "no other compose project runs"; return 0; fi
  # shellcheck disable=SC2046 # one container id per word
  "${DOCKER_DIR}/bin/docker" -H "${DOCKER_SOCK}" stop $(awk '{ print $1 }' <<<"${others}") >/dev/null
  info "stopped the containers of: $(awk '{ print $2 }' <<<"${others}" | sort -u | tr '\n' ' ')"
}

# One environment at a time (ADR 0008): Mijn Bureau runs on K3s in this guest.
# Stop K3s and its pods so they do not take the memory; it starts again at the
# guest's next boot (Mijn Bureau's start boots the guest).
phase_park() {
  log "park the other environments (K3s, other compose projects)"
  if [[ "${DRY_RUN}" -eq 1 ]]; then echo "DRY-RUN: systemctl stop k3s; /usr/local/bin/k3s-killall.sh"; park_other_compose_projects; return 0; fi
  if systemctl is-active --quiet k3s 2>/dev/null; then
    run systemctl stop k3s
  fi
  if [[ -x /usr/local/bin/k3s-killall.sh ]]; then
    run /usr/local/bin/k3s-killall.sh >/dev/null 2>&1 || true
  fi
  info "K3s is stopped"
  park_other_compose_projects
}

# Docker Engine and the compose plugin, pinned static binaries, as a unit of
# our own (dawo-docker, own socket and data root) next to K3s's containerd.
# Shared with Valtimo and Nextcloud Common Ground: the unit below MUST equal
# the one in apps/valtimo/deploy.sh (tests/test-tezza-driver.sh).
phase_docker() {
  log "Docker Engine ${DOCKER_URL##*/} and compose"
  download_verified "${DOCKER_URL:?}" "${DOCKER_SHA:?}" "${DOWNLOADS}/${DOCKER_URL##*/}"
  download_verified "${COMPOSE_URL:?}" "${COMPOSE_SHA:?}" "${DOWNLOADS}/docker-compose"
  if [[ "${DRY_RUN}" -eq 1 ]]; then echo "DRY-RUN: unpack into ${DOCKER_DIR}, install dawo-docker.service, start it"; park_other_compose_projects; return 0; fi
  if ! cmp -s "${DOCKER_DIR}/bin/.sha256" <(printf '%s\n' "${DOCKER_SHA}") 2>/dev/null; then
    rm -rf "${DOCKER_DIR:?}/bin"; mkdir -p "${DOCKER_DIR}/bin"
    tar -xzf "${DOWNLOADS}/${DOCKER_URL##*/}" -C "${DOCKER_DIR}/bin" --strip-components=1
    printf '%s\n' "${DOCKER_SHA}" > "${DOCKER_DIR}/bin/.sha256"
  fi
  mkdir -p "${DOCKER_DIR}/cli-plugins"
  install -m 0755 "${DOWNLOADS}/docker-compose" "${DOCKER_DIR}/cli-plugins/docker-compose"
  mkdir -p /root/.docker && ln -sfn "${DOCKER_DIR}/cli-plugins" /root/.docker/cli-plugins
  # BEGIN dawo-docker.service
  cat > /etc/systemd/system/dawo-docker.service.new <<EOF
[Unit]
Description=Docker Engine for the compose environments (dawo-appliance #246, #250)
After=network-online.target
Wants=network-online.target

[Service]
Environment=PATH=${DOCKER_DIR}/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=${DOCKER_DIR}/bin/dockerd --host=unix:///run/dawo-docker.sock --data-root=/var/lib/dawo-docker --exec-root=/run/dawo-docker --pidfile=/run/dawo-docker.pid --max-concurrent-downloads=2
Restart=on-failure
LimitNOFILE=1048576
Delegate=yes
KillMode=process

[Install]
WantedBy=
EOF
  # END dawo-docker.service
  if ! cmp -s /etc/systemd/system/dawo-docker.service.new /etc/systemd/system/dawo-docker.service; then
    mv -f /etc/systemd/system/dawo-docker.service.new /etc/systemd/system/dawo-docker.service
    systemctl daemon-reload
    systemctl try-restart dawo-docker
  else
    rm -f /etc/systemd/system/dawo-docker.service.new
  fi
  systemctl start dawo-docker
  local _
  for _ in $(seq 1 60); do
    "${DOCKER_DIR}/bin/docker" -H unix:///run/dawo-docker.sock info >/dev/null 2>&1 && break
    sleep 1
  done
  "${DOCKER_DIR}/bin/docker" -H unix:///run/dawo-docker.sock info >/dev/null 2>&1 || die "dockerd did not start"
  info "Docker Engine runs ($("${DOCKER_DIR}/bin/docker" -H unix:///run/dawo-docker.sock version --format '{{.Server.Version}}'))"
  # The engine just started: containers of another environment with a
  # restart policy are back. Park them again.
  park_other_compose_projects
}

# Upstream's packaging at the pinned commit; the commit hash verifies the files.
phase_source() {
  log "tezza-packaging at ${TZ_REV:?}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then echo "DRY-RUN: git fetch --depth 1 ${TZ_REPO:?} ${TZ_REV}; verify HEAD"; return 0; fi
  if [[ -d "${SRC_DIR}/.git" ]] && [[ "$(git -C "${SRC_DIR}" rev-parse HEAD 2>/dev/null)" == "${TZ_REV}" ]]; then
    info "already at ${TZ_REV:0:12}"; return 0
  fi
  mkdir -p "${SRC_DIR}"
  [[ -d "${SRC_DIR}/.git" ]] || git -C "${SRC_DIR}" init -q
  git -C "${SRC_DIR}" remote remove origin >/dev/null 2>&1 || true
  git -C "${SRC_DIR}" remote add origin "${TZ_REPO:?}"
  git -C "${SRC_DIR}" fetch -q --depth 1 origin "${TZ_REV}" || git -C "${SRC_DIR}" fetch -q origin
  git -C "${SRC_DIR}" -c advice.detachedHead=false checkout -q "${TZ_REV}"
  [[ "$(git -C "${SRC_DIR}" rev-parse HEAD)" == "${TZ_REV}" ]] || die "tezza-packaging is not at ${TZ_REV}"
  info "at ${TZ_REV:0:12} (verified by the commit hash)"
}

phase_pull() {
  log "pull the images of the document base (by digest)"
  compose pull --quiet "${SERVICES[@]}"
}

# Upstream's README: the network is created first (it is external).
phase_up() {
  log "start Tezza (docker compose up -d: ${SERVICES[*]})"
  if [[ "${DRY_RUN}" -eq 1 ]]; then echo "DRY-RUN: docker network create -d bridge dev_network"
  elif ! "${DOCKER_DIR}/bin/docker" -H "${DOCKER_SOCK}" network inspect dev_network >/dev/null 2>&1; then
    "${DOCKER_DIR}/bin/docker" -H "${DOCKER_SOCK}" network create -d bridge dev_network >/dev/null
    info "network dev_network created"
  fi
  compose up -d "${SERVICES[@]}"
}

# Ready when Keycloak's realm, Alfresco's readiness probe and the Tezza app
# answer. Bounded: 30 minutes (the first start creates the repository).
phase_ready() {
  log "wait until Tezza is ready"
  if [[ "${DRY_RUN}" -eq 1 ]]; then echo "DRY-RUN: wait for :8181 realm tezza, :8080 Alfresco readiness, :8082"; return 0; fi
  local waited=0 url
  for url in http://localhost:8181/auth/realms/tezza \
             http://localhost:8080/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready- \
             http://localhost:8082/; do
    until curl -fsS -o /dev/null --max-time 5 "${url}"; do
      [[ "${waited}" -ge 1800 ]] && die "${url} does not answer after ${waited}s"
      sleep 5; waited=$((waited + 5))
    done
    info "${url} answers (${waited}s)"
  done
}

alfresco() { # alfresco METHOD PATH [JSON]: Alfresco's REST API as upstream's admin
  curl -sS -o /dev/null -w '%{http_code}' --max-time 120 -u admin:admin -X "$1" -H 'Content-Type: application/json' \
    "http://localhost:8080/alfresco/api/-default-/public/alfresco/versions/1/$2" ${3:+-d "$3"}
}

# Upstream's own first-run step ("01. Setup" in the Admin Tools: sites,
# groups, templates, demo users in groups), once; then the login dawo / dawo
# (#258): a user in upstream's LDAP (Keycloak signs in against it), in
# Alfresco's administrators, and an admin of Keycloak's own console.
phase_setup() {
  log "Tezza's setup (upstream's '01. Setup') and the login dawo / dawo"
  if [[ "${DRY_RUN}" -eq 1 ]]; then echo "DRY-RUN: GET /alfresco/service/contezza/config/setup; ldapadd dawo; Alfresco admin dawo; kcadm master dawo"; return 0; fi
  if [[ ! -f "${STATE_DIR}/setup.done" ]]; then
    curl -fsS -o "${STATE_DIR}/setup.log" --max-time 1800 -u admin:admin \
      http://localhost:8080/alfresco/service/contezza/config/setup \
      || die "upstream's setup did not run (see ${STATE_DIR}/setup.log)"
    touch "${STATE_DIR}/setup.done"
    info "upstream's setup done"
  else
    info "upstream's setup was done before"
  fi
  # LDAP (upstream's users.ldif shape).
  if ! compose exec -T openldap ldapsearch -x -H ldap://localhost -b ou=Users,dc=contezza,dc=local -D cn=admin,dc=contezza,dc=local -w admin "(uid=dawo)" uid 2>/dev/null | grep -q '^uid: dawo'; then
    compose exec -T openldap ldapadd -x -H ldap://localhost -D cn=admin,dc=contezza,dc=local -w admin >/dev/null <<'EOF'
dn: cn=dawo,ou=Users,dc=contezza,dc=local
objectClass: person
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: top
cn: dawo
userpassword: dawo
givenname: Dawo
sn: Demo
mail: dawo@example.com
uid: dawo
ou: Management
EOF
  fi
  # Alfresco: the person (as LDAP sync would make it) and an administrator.
  local code
  code="$(alfresco POST people '{"id":"dawo","firstName":"Dawo","lastName":"Demo","email":"dawo@example.com","password":"dawo"}')"
  [[ "${code}" == 201 || "${code}" == 409 ]] || info "Alfresco person dawo: HTTP ${code}"
  code="$(alfresco POST groups/GROUP_ALFRESCO_ADMINISTRATORS/members '{"id":"dawo","memberType":"PERSON"}')"
  [[ "${code}" == 201 || "${code}" == 409 ]] || info "Alfresco administrators: HTTP ${code}"
  # Keycloak's own console (master realm), next to upstream's admin / admin.
  local kc=(/opt/keycloak/bin/kcadm.sh) cfg=(--config /tmp/dawo-kcadm.config)
  if compose exec -T identity "${kc[@]}" config credentials "${cfg[@]}" --server http://localhost:8181/auth \
       --realm master --user admin --password admin >/dev/null 2>&1; then
    if ! compose exec -T identity "${kc[@]}" get users "${cfg[@]}" -r master -q username=dawo -q exact=true --fields username 2>/dev/null | grep -q '"dawo"'; then
      compose exec -T identity "${kc[@]}" create users "${cfg[@]}" -r master -s username=dawo -s enabled=true >/dev/null
    fi
    compose exec -T identity "${kc[@]}" set-password "${cfg[@]}" -r master --username dawo --new-password dawo >/dev/null
    compose exec -T identity "${kc[@]}" add-roles "${cfg[@]}" -r master --uusername dawo --rolename admin >/dev/null
  fi
  info "login dawo / dawo (Tezza, Share, Admin Tools, Keycloak console)"
}

# The other environment starts: stop the containers (they keep their data).
do_stop() {
  log "stop the Tezza containers"
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
  setup) phase_setup ;;
  *) die "unknown or missing --phase (park, docker, source, pull, up, ready, setup)" ;;
esac
