# shellcheck shell=bash
# launch: start, stop and list environments (ADR 0008,
# docs/adr/0008-launch-environments.md). Packaged by nix/launch.nix, which sets
# LAUNCH_CATALOG to the catalogue JSON built from environments/.
#
# Launch is meant to become a project of its own: nothing in here is specific
# to one workplace. Paths and limits come from the environment:
#   LAUNCH_CATALOG        the catalogue JSON (set by the package)
#   LAUNCH_CONFIG         this machine's settings, written by the NixOS module
#                         services.launch (default /etc/launch/config.json):
#                         dataPath, reserveGiB, internetUrl, and per environment
#                         the systemd units that start and stop it
#   LAUNCH_DATA_PATH      where environments keep their data (default: config, else /var/lib/launch)
#   LAUNCH_RESERVE_GIB    memory kept for the workplace itself (default: config, else 6)
#   LAUNCH_INTERNET_URL   reachable when there is internet (default: config, else https://github.com/)
#   LAUNCH_SYSTEMCTL      (tests) instead of systemctl
#   LAUNCH_MEMINFO        (tests) a meminfo file instead of /proc/meminfo
#   LAUNCH_KVM_DEVICE     (tests) instead of /dev/kvm
#   LAUNCH_FREE_GIB       (tests) free space instead of asking df
#
# Messages are in Dutch: the people who use this are Dutch civil servants.
#
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail

catalog="${LAUNCH_CATALOG:?LAUNCH_CATALOG is not set}"
config="${LAUNCH_CONFIG:-/etc/launch/config.json}"
[[ -r "${config}" ]] || config=/dev/null
conf() { jq -r "$1 // empty" "${config}" 2>/dev/null || true; }
data_path="${LAUNCH_DATA_PATH:-$(conf .dataPath)}"; data_path="${data_path:-/var/lib/launch}"
reserve_gib="${LAUNCH_RESERVE_GIB:-$(conf .reserveGiB)}"; reserve_gib="${reserve_gib:-6}"
internet_url="${LAUNCH_INTERNET_URL:-$(conf .internetUrl)}"; internet_url="${internet_url:-https://github.com/}"
systemctl_bin="${LAUNCH_SYSTEMCTL:-systemctl}"
meminfo="${LAUNCH_MEMINFO:-/proc/meminfo}"
kvm_device="${LAUNCH_KVM_DEVICE:-/dev/kvm}"

usage() {
  cat <<'EOF'
Gebruik:
  launch                        de omgevingen die je kunt starten
  launch <omgeving> [--yes]     een omgeving starten (--yes: niet vragen bij een waarschuwing)
  launch --check <omgeving>     alleen controleren of deze laptop genoeg heeft (--json voor de Launcher)
  launch --stop <omgeving>      een omgeving stoppen
  launch --status [--json]      welke omgevingen antwoorden, en waar
  launch --list [--json]        de catalogus (--json: voor de Launcher)
EOF
}

env_json() { jq -e --arg id "$1" '.environments[] | select(.id == $id)' "$catalog"; }
field() { jq -r --arg id "$1" ".environments[] | select(.id == \$id) | $2" "$catalog"; }

require_env() {
  if ! env_json "$1" >/dev/null 2>&1; then
    echo "launch: onbekende omgeving '$1'. Kies uit:" >&2
    jq -r '.environments[].id' "$catalog" >&2
    exit 1
  fi
}

list() {
  if [[ "${1:-}" == "--json" ]]; then
    jq . "$catalog"
  else
    jq -r '.environments[] | "\(.id)\t\(.title) \(.version)\n\t\(.summary)\n\t\(.url)"' "$catalog"
  fi
}

# Free GiB on the data path (the nearest existing directory).
free_gib() {
  if [[ -n "${LAUNCH_FREE_GIB:-}" ]]; then echo "${LAUNCH_FREE_GIB}"; return; fi
  local p="${data_path}"
  while [[ ! -d "${p}" && "${p}" != "/" ]]; do p="$(dirname "${p}")"; done
  df --output=avail -B1G "${p}" | tail -n 1 | tr -d ' '
}

# One line per shortfall, in Dutch; nothing when the laptop has enough.
problems() {
  local id="$1" title need_mem need_disk total have
  title="$(field "${id}" .title)"
  need_mem="$(field "${id}" .needs.memory_gib)"
  need_disk="$(field "${id}" .needs.disk_gib)"

  total="$(awk '/^MemTotal:/ { printf "%d", $2 / 1048576 + 0.5 }' "${meminfo}")"
  if (( total < need_mem + reserve_gib )); then
    echo "Deze laptop heeft ${total} GB geheugen; de ${title}-omgeving heeft ongeveer $(( need_mem + reserve_gib )) GB nodig (${need_mem} GB voor de omgeving en ${reserve_gib} GB voor de werkplek). Het kan traag worden of mislukken."
  fi

  have="$(free_gib)"
  if (( have < need_disk )); then
    echo "Er is nog ${have} GB vrij op de opslag (${data_path}); de ${title}-omgeving heeft ongeveer ${need_disk} GB nodig. Gebruik een grotere USB-schijf of maak ruimte vrij."
  fi

  if [[ "$(field "${id}" .needs.kvm)" == true && ! -e "${kvm_device}" ]]; then
    echo "Hardware-virtualisatie (VT-x/AMD-V) staat uit of ontbreekt; de ${title}-omgeving kan dan niet starten. Zet het aan in de BIOS-instellingen."
  fi

  if [[ "$(field "${id}" .needs.internet)" == true ]] \
     && ! curl -sS --max-time 8 -o /dev/null "${internet_url}" 2>/dev/null; then
    echo "Er lijkt geen internet te zijn; de eerste keer downloadt de ${title}-omgeving haar onderdelen."
  fi
}

check() {
  local id="$1" json="${2:-}" out
  require_env "${id}"
  out="$(problems "${id}")"
  if [[ "${json}" == "--json" ]]; then
    jq -n --arg id "${id}" --arg p "${out}" '{id: $id, ok: ($p == ""), problems: ($p | split("\n") | map(select(. != "")))}'
  elif [[ -z "${out}" ]]; then
    echo "Alles in orde voor de $(field "${id}" .title)-omgeving."
  else
    echo "Let op voordat je de $(field "${id}" .title)-omgeving start:"
    while IFS= read -r line; do echo "  - ${line}"; done <<<"${out}"
  fi
  [[ -z "${out}" ]]
}

# The systemd units that start and stop an environment on this machine.
units_of() { jq -r --arg id "$1" '.environments[$id].units[]? // empty' "${config}" 2>/dev/null || true; }

# Whether any of the environment's units is active (starting or running).
units_active() {
  local u
  while IFS= read -r u; do
    [[ -n "${u}" ]] || continue
    if "${systemctl_bin}" is-active --quiet "${u}"; then return 0; fi
  done < <(units_of "$1")
  return 1
}

# Whether each environment answers at its health URL; while its units run but
# it does not answer yet, it is starting.
status() {
  local json="${1:-}" id title url answers state out="[]"
  while IFS=$'	' read -r id title url; do
    answers=false
    if curl -sS --max-time 4 -o /dev/null "${url}" 2>/dev/null; then answers=true; fi
    if [[ "${answers}" == true ]]; then state=ready
    elif units_active "${id}"; then state=starting
    else state=stopped; fi
    if [[ "${json}" == "--json" ]]; then
      out="$(jq --arg id "${id}" --arg url "${url}" --arg st "${state}" --argjson up "${answers}" '. + [{id: $id, url: $url, state: $st, answers: $up}]' <<<"${out}")"
    else
      case "${state}" in
        ready) echo "${title}: klaar op ${url}" ;;
        starting) echo "${title}: wordt gestart" ;;
        *) echo "${title}: niet actief" ;;
      esac
    fi
  done < <(jq -r '.environments[] | [.id, .title, .health.url] | @tsv' "$catalog")
  if [[ "${json}" == "--json" ]]; then jq . <<<"${out}"; fi
}

start() {
  local id="$1" yes="${2:-}" answer
  require_env "${id}"
  if ! check "${id}"; then
    if [[ "${yes}" != "--yes" ]]; then
      if [[ -t 0 ]]; then
        read -r -p "Toch starten? [j/N] " answer
        case "${answer,,}" in j | ja | y | yes) ;; *) echo "Niet gestart."; exit 3 ;; esac
      else
        echo "Niet gestart. Gebruik --yes om toch te starten." >&2
        exit 3
      fi
    fi
  fi
  mapfile -t units < <(units_of "${id}")
  if (( ${#units[@]} == 0 )); then
    echo "launch ${id}: starten is op deze machine niet ingericht (geen units in ${LAUNCH_CONFIG:-/etc/launch/config.json})." >&2
    exit 2
  fi
  "${systemctl_bin}" start --no-block "${units[@]}"
  echo "De $(field "${id}" .title)-omgeving wordt gestart. Volg het met: launch --status"
  echo "Daarna te openen op $(field "${id}" .url)"
}

stop() {
  local id="$1" i
  require_env "${id}"
  mapfile -t units < <(units_of "${id}")
  if (( ${#units[@]} == 0 )); then
    echo "launch --stop ${id}: stoppen is op deze machine niet ingericht." >&2
    exit 2
  fi
  # Reverse order: what was started last stops first.
  for (( i = ${#units[@]} - 1; i >= 0; i-- )); do "${systemctl_bin}" stop "${units[i]}"; done
  echo "De $(field "${id}" .title)-omgeving is gestopt."
}

case "${1:-}" in
  "" | --list) list "${2:-}" ;;
  -h | --help) usage ;;
  --check) [[ -n "${2:-}" ]] || { usage >&2; exit 1; }; check "$2" "${3:-}" || exit 3 ;;
  --status) status "${2:-}" ;;
  --stop) [[ -n "${2:-}" ]] || { usage >&2; exit 1; }; stop "$2" ;;
  -*) usage >&2; exit 1 ;;
  *) start "$1" "${2:-}" ;;
esac
