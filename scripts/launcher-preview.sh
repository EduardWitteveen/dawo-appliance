#!/usr/bin/env bash
#
# Try the Launcher on a development machine, without the rest (#282, #284):
# the real launcher.py, launcher.html, `launch` and catalogue (built with Nix),
# with a fake systemctl. Every environment starts stopped.
#
#   haalcentraal  real: Haal Centraal (launch/haalcentraal) with Docker, ready
#                 in seconds; for the browser test it fails at step N when
#                 the file <state>/haalcentraal-fail-at holds N
#   the others    fake: a start shows their first step and stays there
#
#   bash scripts/launcher-preview.sh [--port 18790]
#   PREVIEW_STATE_DIR=<dir> ...      keep the state in <dir> (for the test)
#
# Runs on Linux or in WSL with Nix and Docker (from the repository root); then
# open http://localhost:18790 (from Windows too: WSL forwards localhost).
# Ctrl-C stops it. Nothing outside the state directory is touched, but the
# Haal Centraal containers (docker compose project haalcentraal).
#
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo="$(pwd)"

port=18790
[[ "${1:-}" == "--port" ]] && port="${2:?--port needs a number}"

# `launch` from this working tree (its wrapper brings jq and the catalogue);
# the page and its server straight from launch/, so an edit shows on reload.
launch="$(nix build --no-link --print-out-paths "path:.#launch")/bin/launch"
catalog="$(grep -o '/nix/store/[^"]*launch-catalog.json' "${launch}" | head -n1)"
[[ -r "${catalog}" ]] || { echo "launcher-preview: no catalogue in ${launch}" >&2; exit 1; }

dir="${PREVIEW_STATE_DIR:-$(mktemp -d)}"
rm -rf "${dir:?}/state"; mkdir -p "${dir}/state"
cleanup() { bash "${repo}/launch/haalcentraal/run.sh" stop || true; }
trap cleanup EXIT

# The catalogue, plus Haal Centraal; the fake environments get a health URL
# that never answers.
python3 - "${catalog}" "${dir}/catalog.json" <<'EOF'
import json, sys
src, dst = sys.argv[1:]
c = json.load(open(src))
for e in c["environments"]:
    e["health"]["url"] = "http://127.0.0.1:9/"
c["environments"].append({
    "id": "haalcentraal", "title": "Haal Centraal", "version": "BRP personen-mock 2.7.0 (test)",
    "summary": "Persoonsgegevens opvragen bij de BRP, met fictieve testpersonen: de testversie van de API van de RvIG. Start in een paar seconden.",
    "url": "http://localhost:18795/", "health": {"url": "http://localhost:18795/"}, "login": "",
})
json.dump(c, open(dst, "w"))
EOF

# This machine's settings: one unit and a progress file per environment.
python3 - "${dir}" <<'EOF'
import json, sys
d = sys.argv[1]
ids = [e["id"] for e in json.load(open(f"{d}/catalog.json"))["environments"]]
envs = {i: {"units": [f"{i}.service"], "progressFile": f"{d}/state/{i}.progress.json"} for i in ids}
json.dump({"dataPath": d, "reserveGiB": 6, "environments": envs}, open(f"{d}/config.json", "w"))
EOF

# The fake systemctl: state is a marker file per unit; Haal Centraal is real.
cat > "${dir}/systemctl" <<EOF
#!/usr/bin/env bash
s="${dir}/state"
cmd="\$1"; shift
[[ "\${1:-}" == --quiet || "\${1:-}" == --no-block ]] && shift
case "\${cmd}" in
  is-active) [[ -e "\${s}/\$1.active" ]] ;;
  is-failed) [[ -e "\${s}/\$1.failed" ]] ;;
  list-jobs) exit 0 ;;
  start) for u in "\$@"; do
           i="\${u%.service}"; rm -f "\${s}/\${u}.failed"; touch "\${s}/\${u}.active"
           if [[ "\${i}" == haalcentraal ]]; then
             ( HAALCENTRAAL_FAIL_AT="\$(cat "${dir}/haalcentraal-fail-at" 2>/dev/null)" \\
                 bash "${repo}/launch/haalcentraal/run.sh" start "\${s}/\${i}.progress.json"
               rc=\$?; rm -f "\${s}/\${u}.active"; [[ \${rc} -eq 0 ]] || touch "\${s}/\${u}.failed" ) >/dev/null 2>&1 &
           else
             t=\$(date +%s)
             printf '{"step":1,"steps":9,"label":"Virtuele machine starten","started":%s,"since":%s,"expected":120,"rest":900}\n' "\$t" "\$t" > "\${s}/\${i}.progress.json"
           fi; done ;;
  stop) for u in "\$@"; do
          i="\${u%.service}"
          [[ "\${i}" == haalcentraal ]] && bash "${repo}/launch/haalcentraal/run.sh" stop >/dev/null 2>&1
          rm -f "\${s}/\${u}.active" "\${s}/\${u}.failed" "\${s}/\${i}.progress.json"; done ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${dir}/systemctl"
printf 'MemTotal: 33554432 kB\nMemAvailable: 30000000 kB\n' > "${dir}/meminfo"
touch "${dir}/kvm" "${dir}/net"

export LAUNCH_CATALOG="${dir}/catalog.json" LAUNCH_CONFIG="${dir}/config.json" LAUNCH_SYSTEMCTL="${dir}/systemctl" \
       LAUNCH_MEMINFO="${dir}/meminfo" LAUNCH_KVM_DEVICE="${dir}/kvm" LAUNCH_FREE_GIB=100 LAUNCH_INTERNET_URL="file://${dir}/net"
echo "launcher-preview: http://localhost:${port}  (state in ${dir}; Ctrl-C stops)"
python3 launch/launcher.py --port "${port}" \
  --page launch/launcher.html --launch "${launch}" --cycle-file "${dir}/no-cycle" --cycle-report "${dir}/rondgang.log"
