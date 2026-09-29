#!/usr/bin/env bash
# Offline test for health/dawo-appliance-status-page.sh (issue #116): the live
# status page, rendered once (STATUS_ONCE=1) with fake curl/systemctl. No
# network, no root, no Nix. Runs on Linux, WSL and Windows Git Bash.
#
#   1. offline, Mijn Bureau at step 8 of 14: internet hint with the demo
#      Wi-Fi, a progress bar at 50 %, elapsed minutes, debug line, refresh
#   2. Mijn Bureau done: an "Open Mijn Bureau" link to the dashboard
#   3. guest skipped (no /dev/kvm): Dutch reason, Mijn Bureau "cannot"
#   4. booted with dawo.debug=0: no debug line
#   5. deployment failed: the failure is shown
#
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAGE="${REPO_ROOT}/health/dawo-appliance-status-page.sh"
[[ -f "${PAGE}" ]] || { echo "status page script not found: ${PAGE}"; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
fakes="${tmp}/bin"
mkdir -p "${fakes}"
cat >"${fakes}/curl" <<'EOF'
#!/usr/bin/env bash
[ "${FAKE_NET:-up}" = up ]
EOF
cat >"${fakes}/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$3" in
  ActiveState) echo "${FAKE_GUEST_STATE:-active}" ;;
  Result) echo "${FAKE_GUEST_RESULT:-success}" ;;
esac
EOF
chmod +x "${fakes}"/*

pass=0
fail=0
ok() { echo "  PASS $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL $*"; fail=$((fail + 1)); }

export STATUS_ONCE=1 STATUS_CURL="${fakes}/curl" STATUS_SYSTEMCTL="${fakes}/systemctl"
export STATUS_PASSWORD_FILE="${tmp}/no-password" STATUS_GUEST_SKIPPED="${tmp}/no-skip"
export STATUS_DATA="${tmp}/data" STATUS_MB="${tmp}/mb" STATUS_MB_START="${tmp}/mb-start"
export STATUS_MB_LOG="${tmp}/mb.log" STATUS_MB_DURATIONS="${tmp}/no-durations"
printf 'quiet\n' >"${tmp}/cmdline"
export STATUS_CMDLINE="${tmp}/cmdline"
printf 'stick: reused dawo-data.ext4 + dawo-images\n' >"${tmp}/data"

render() { export STATUS_OUT="${tmp}/page.$1.html"; bash "${PAGE}"; cat "${STATUS_OUT}"; }

# 1. offline, step 8 of 14.
printf 'wordt uitgerold: stap 8 van 14 (deploy)\n' >"${tmp}/mb"
echo $(( $(date +%s) - 720 )) >"${tmp}/mb-start"
p="$(FAKE_NET=down render 1)"
if grep -q 'http-equiv="refresh"' <<<"$p" && grep -q 'DawoDawo' <<<"$p" \
   && grep -q 'stap 8 van 14' <<<"$p" && grep -q "width:50%" <<<"$p" \
   && grep -q 'bezig: 12 min' <<<"$p" && grep -q 'Debug-modus' <<<"$p" \
   && grep -q 'op de USB-stick, blijft bewaard' <<<"$p" \
   && grep -q 'Deze stap duurt meestal ongeveer 6 minuten' <<<"$p"; then
  ok "offline + step 8/14: Wi-Fi hint, 50 % bar, 12 min elapsed, typical duration, debug line, storage, auto refresh"
else
  bad "offline + step 8/14"; echo "$p"
fi

# 1b. signs of life while deploying (#132): moving indicator, attempt, time
#     since the last log write, the last log line (colour codes removed).
printf '%s\n' '2026-09-29T01:00:00Z t=85s phase 8/14 deploy: attempt 1' \
  '2026-09-29T01:05:00Z t=385s phase 8/14 deploy: FAILED after 300s' \
  '2026-09-29T01:05:30Z t=415s phase 8/14 deploy: attempt 2' \
  "$(printf 'Upgrading release=keycloak, chart=\033[1mcharts/keycloak\033[0m')" '' >"${tmp}/mb.log"
touch -d '-20 seconds' "${tmp}/mb.log"
p="$(FAKE_NET=up render 1b)"
if grep -q "class='spin'" <<<"$p" && grep -q 'poging 2 van 3' <<<"$p" \
   && grep -qE 'laatste activiteit: (19|2[0-9]) s geleden' <<<"$p" \
   && grep -q 'Upgrading release=keycloak, chart=charts/keycloak' <<<"$p" \
   && ! grep -q $'\033' <<<"$p" && grep -q '<title>DAWO appliance &mdash; bezig</title>' <<<"$p" \
   && grep -q 'Bezig: Mijn Bureau wordt uitgerold' <<<"$p"; then
  ok "deploying: spinner, 'poging 2 van 3', last activity ~20 s ago, last log line without colour codes, title says bezig"
else
  bad "deploying: signs of life"; echo "$p"
fi

# 1c. how long the step took last time on this machine (#143): the latest
#     entry for the running phase wins.
printf '%s\n' '8 412' '10 70' '8 338' >"${tmp}/durations"
p="$(STATUS_MB_DURATIONS="${tmp}/durations" FAKE_NET=up render 1c)"
if grep -q 'Vorige keer duurde deze stap op deze laptop 6 min' <<<"$p" && ! grep -q 'duurt meestal' <<<"$p"; then
  ok "deploying: 'vorige keer duurde deze stap op deze laptop 6 min' from the durations kept on the stick"
else
  bad "deploying: previous duration"; echo "$p"
fi

# 2. done.
printf 'klaar: Mijn Bureau is uitgerold (1800s)\n' >"${tmp}/mb"
p="$(FAKE_NET=up render 2)"
if grep -q "href='https://bureaublad.dawo.internal'" <<<"$p" && grep -q 'Mijn Bureau staat klaar' <<<"$p" \
   && grep -q '<b>johndoe</b>' <<<"$p" && grep -q 'myStrongPassword123' <<<"$p"; then
  ok "done: 'Open Mijn Bureau' links to the dashboard and the demo login is shown"
else
  bad "done"; echo "$p"
fi

# 3. guest skipped.
printf 'no /dev/kvm: virtualisation is off\n' >"${tmp}/skip"
: >"${tmp}/mb"
p="$(STATUS_GUEST_SKIPPED="${tmp}/skip" FAKE_NET=up render 3)"
if grep -q 'hardwarevirtualisatie' <<<"$p" && grep -q 'kan niet worden uitgerold zonder virtuele machine' <<<"$p"; then
  ok "guest skipped: Dutch reason and 'Mijn Bureau cannot be deployed'"
else
  bad "guest skipped"; echo "$p"
fi

# 4. dawo.debug=0.
printf 'quiet dawo.debug=0\n' >"${tmp}/cmdline"
p="$(FAKE_NET=up render 4)"
if ! grep -q 'Debug-modus' <<<"$p"; then ok "dawo.debug=0: no debug line"; else bad "dawo.debug=0"; fi

# 5. failed.
printf 'mislukt bij stap 8 van 14 (deploy); zie mijnbureau.txt op de USB-stick\n' >"${tmp}/mb"
p="$(FAKE_NET=up render 5)"
if grep -q 'mislukt bij stap 8 van 14' <<<"$p" && grep -q 'details staan op de USB-stick' <<<"$p" \
   && grep -q 'banner-fail' <<<"$p" && grep -q 'Start de laptop' <<<"$p" \
   && grep -q '<title>DAWO appliance &mdash; mislukt</title>' <<<"$p"; then
  ok "failed: red banner, the failure, what to do next and where the details are"
else
  bad "failed"; echo "$p"
fi

echo
echo "test-status-page: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
