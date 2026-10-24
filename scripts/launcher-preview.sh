#!/usr/bin/env bash
#
# Try the Launcher on a development machine, without the rest (#282): the
# real launcher.py, launcher.html, `launch` and catalogue (built with Nix),
# with a fake systemctl, fake progress files and local health URLs, so every
# card shows a state worth looking at:
#
#   mijn-bureau             ready (its URL answers, nothing runs)
#   tezza                   failed (the unit failed, its URL answers, an error)
#   nextcloud-commonground  starting, its step far over last time's duration
#   valtimo                 stopped
#
# "Starten" and "Stoppen" work on the fake: a start makes the environment
# "starting" (a fresh step), a stop makes it stopped.
#
#   bash scripts/launcher-preview.sh [--port 18790]
#
# Runs on Linux or in WSL with Nix (from the repository root); then open
# http://localhost:18790 (from Windows too: WSL forwards localhost).
# Ctrl-C stops it. Nothing outside a temporary directory is touched.
#
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

port=18790
[[ "${1:-}" == "--port" ]] && port="${2:?--port needs a number}"

# `launch` from this working tree (its wrapper brings jq and the catalogue);
# the page and its server straight from launch/, so an edit shows on reload.
launch="$(nix build --no-link --print-out-paths "path:.#launch")/bin/launch"
catalog="$(grep -o '/nix/store/[^"]*launch-catalog.json' "${launch}" | head -n1)"
[[ -r "${catalog}" ]] || { echo "launcher-preview: no catalogue in ${launch}" >&2; exit 1; }

dir="$(mktemp -d)"
pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; rm -rf "${dir}"; }
trap cleanup EXIT
mkdir -p "${dir}/state" "${dir}/www"
echo ok > "${dir}/www/index.html"

# Health URLs on local ports; an environment answers while its port serves.
declare -A hport=([mijn-bureau]=$((port + 1)) [tezza]=$((port + 2)) [nextcloud-commonground]=$((port + 3)) [valtimo]=$((port + 4)))
python3 - "${catalog}" "${dir}/catalog.json" "${hport[mijn-bureau]}" "${hport[tezza]}" "${hport[nextcloud-commonground]}" "${hport[valtimo]}" <<'EOF'
import json, sys
src, dst, *ports = sys.argv[1:]
c = json.load(open(src))
order = ["mijn-bureau", "tezza", "nextcloud-commonground", "valtimo"]
for e in c["environments"]:
    if e["id"] in order:
        e["health"]["url"] = f"http://127.0.0.1:{ports[order.index(e['id'])]}/"
json.dump(c, open(dst, "w"))
EOF
for id in mijn-bureau tezza; do
  python3 -m http.server "${hport[$id]}" --bind 127.0.0.1 --directory "${dir}/www" >/dev/null 2>&1 & pids+=($!)
done

# This machine's settings: one unit and a progress file per environment.
python3 - "${dir}" <<'EOF'
import json, sys
d = sys.argv[1]
envs = {i: {"units": [f"{i}.service"], "progressFile": f"{d}/state/{i}.progress.json"}
        for i in ["mijn-bureau", "tezza", "nextcloud-commonground", "valtimo"]}
json.dump({"dataPath": d, "reserveGiB": 6, "environments": envs}, open(f"{d}/config.json", "w"))
EOF

now="$(date +%s)"
# tezza: failed, with the runner's error.
touch "${dir}/state/tezza.service.failed"
cat > "${dir}/state/tezza.progress.json" <<EOF
{"step":7,"steps":9,"label":"Tezza starten","started":$((now - 1200)),"since":$((now - 1700)),"expected":649,"rest":500,
 "error":"Deze stap is drie keer mislukt. De details staan in tezza.txt op de USB-schijf."}
EOF
# nextcloud-commonground: starting, 49 minutes into a step that took 7 last time.
touch "${dir}/state/nextcloud-commonground.service.active"
cat > "${dir}/state/nextcloud-commonground.progress.json" <<EOF
{"step":8,"steps":9,"label":"Wachten tot Nextcloud klaar is","started":$((now - 2940)),"since":$((now - 5040)),"expected":446,"rest":133,
 "detail":"waiting for Nextcloud (http://localhost:8609/status.php), 2940s","activity":$((now - 12))}
EOF

# The fake systemctl: state is a marker file per unit.
cat > "${dir}/systemctl" <<EOF
#!/usr/bin/env bash
s="${dir}/state"
cmd="\$1"; shift
[[ "\${1:-}" == --quiet || "\${1:-}" == --no-block ]] && shift
case "\${cmd}" in
  is-active) [[ -e "\${s}/\$1.active" ]] ;;
  is-failed) [[ -e "\${s}/\$1.failed" ]] ;;
  list-jobs) exit 0 ;;
  start) for u in "\$@"; do rm -f "\${s}/\${u}.failed"; touch "\${s}/\${u}.active"
           i="\${u%.service}"; t=\$(date +%s)
           printf '{"step":1,"steps":9,"label":"Virtuele machine starten","started":%s,"since":%s,"expected":120,"rest":900}\n' "\$t" "\$t" > "\${s}/\${i}.progress.json"; done ;;
  stop) for u in "\$@"; do rm -f "\${s}/\${u}.active" "\${s}/\${u}.failed"; done ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${dir}/systemctl"
printf 'MemTotal: 33554432 kB\nMemAvailable: 30000000 kB\n' > "${dir}/meminfo"
touch "${dir}/kvm" "${dir}/net"

export LAUNCH_CATALOG="${dir}/catalog.json" LAUNCH_CONFIG="${dir}/config.json" LAUNCH_SYSTEMCTL="${dir}/systemctl" \
       LAUNCH_MEMINFO="${dir}/meminfo" LAUNCH_KVM_DEVICE="${dir}/kvm" LAUNCH_FREE_GIB=100 LAUNCH_INTERNET_URL="file://${dir}/net"
echo "launcher-preview: http://localhost:${port}  (Ctrl-C stops)"
python3 launch/launcher.py --port "${port}" \
  --page launch/launcher.html --launch "${launch}" --cycle-file "${dir}/no-cycle" --cycle-report "${dir}/rondgang.log"
