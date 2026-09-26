#!/usr/bin/env bash
#
# dawo-appliance-open-dashboard.sh — the appliance's last install-plan step
# ("wait until Mijn Bureau is healthy", "open Mijn Bureau in the browser").
#
# Waits (bounded) for dawo-appliance-health.sh --wait, then opens the Mijn
# Bureau dashboard in the user's default browser (xdg-open; Firefox on the
# DAWO workplace, which trusts the appliance CA through its policy file). If
# the deployment is not healthy within the timeout, a kdialog message lists
# the checks that are still WAIT/FAIL instead of opening a browser that would
# only show an error page.
#
# Meant to run as an XDG autostart entry of the `dawo` Plasma session (Slice 7;
# see health/README.md for the .desktop entry). Runs as the logged-in user;
# never needs root.
#
# Environment (all optional; tests use them to inject fakes):
#   DASHBOARD_URL       URL to open (default https://bureaublad.dawo.internal)
#   DASHBOARD_TIMEOUT   seconds to wait for health (default 1800)
#   DASHBOARD_HEALTH    path of the health script (default: next to this file)
#   DASHBOARD_XDG_OPEN  browser opener (default xdg-open)
#   DASHBOARD_KDIALOG   dialog command (default kdialog)
#   DASHBOARD_LOG       append the health progress to this file (default: none)
#   HEALTH_*            passed through to the health script
#
# Exit codes: 0 dashboard opened, 1 not healthy in time (dialog shown),
#             2 the browser could not be started.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEALTH="${DASHBOARD_HEALTH:-${here}/dawo-appliance-health.sh}"
URL="${DASHBOARD_URL:-https://bureaublad.dawo.internal}"
TIMEOUT="${DASHBOARD_TIMEOUT:-1800}"
OPEN_BIN="${DASHBOARD_XDG_OPEN:-xdg-open}"
KDIALOG_BIN="${DASHBOARD_KDIALOG:-kdialog}"
LOG="${DASHBOARD_LOG:-/dev/null}"

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

report=""
rc=0
SECONDS=0
report="$(bash "${HEALTH}" --wait --timeout "${TIMEOUT}" 2>>"${LOG}")" || rc=$?
elapsed="${SECONDS}"

if [ "${rc}" -eq 0 ]; then
  echo "dawo-appliance: Mijn Bureau is healthy; opening ${URL}"
  if "${OPEN_BIN}" "${URL}"; then
    exit 0
  fi
  echo "dawo-appliance: could not start a browser for ${URL}" >&2
  exit 2
fi

failing="$(printf '%s\n' "${report}" | grep -v '^OK' || true)"
[ -n "${failing}" ] || failing="(health check exited ${rc} without a report; see ${LOG})"
# Exit 1 is "not healthy within the timeout"; anything else means the check
# itself failed, after ${elapsed}s rather than the full timeout (issue #98).
if [ "${rc}" -eq 1 ]; then
  why_nl="De gezondheidscontrole was na ${elapsed} seconden nog niet geslaagd."
  why_en="the health check did not pass within ${elapsed}s"
else
  why_nl="De gezondheidscontrole is na ${elapsed} seconden afgebroken (foutcode ${rc})."
  why_en="the health check failed after ${elapsed}s (exit ${rc})"
fi
echo "dawo-appliance: Mijn Bureau not healthy: ${why_en}:" >&2
printf '%s\n' "${failing}" >&2

"${KDIALOG_BIN}" \
  --title "DAWO appliance (experimenteel / experimental)" \
  --icon dialog-warning \
  --sorry "<h3>Mijn Bureau is nog niet bereikbaar</h3>
<p>${why_nl} De browser is daarom niet geopend. Nog niet in orde:</p>
<pre>$(html_escape "${failing}")</pre>
<p>Opnieuw controleren: <tt>dawo-appliance-health --once</tt>; daarna
<tt>${URL}</tt> openen.</p>
<hr/>
<p><small>English: ${why_en}, so the dashboard was not opened. Re-check with <tt>dawo-appliance-health --once</tt>,
then open <tt>${URL}</tt>.</small></p>" \
  >/dev/null 2>&1 || true
exit 1
