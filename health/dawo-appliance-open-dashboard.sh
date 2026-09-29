#!/usr/bin/env bash
#
# dawo-appliance-open-dashboard.sh — the appliance's last install-plan step
# ("wait until Mijn Bureau is healthy", "open Mijn Bureau in the browser").
#
# Waits (bounded) for dawo-appliance-health.sh --wait, then opens the Mijn
# Bureau dashboard in the user's default browser (xdg-open; Firefox on the
# DAWO workplace, which trusts the appliance CA through its policy file). If
# the deployment is not healthy within the timeout, a desktop notification
# names the checks that are still WAIT/FAIL instead of opening a browser that
# would only show an error page. Notifications stack in the notification area;
# the one status window at login is health/dawo-appliance-welcome.sh (#106).
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
#   DASHBOARD_NOTIFY    notification command (default notify-send)
#   DASHBOARD_LOG       append the health progress to this file (default: none)
#   HEALTH_*            passed through to the health script
#
# Exit codes: 0 dashboard opened, 1 not healthy in time (notification sent)
#             or the guest was deliberately skipped (the welcome window says why),
#             2 the browser could not be started.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEALTH="${DASHBOARD_HEALTH:-${here}/dawo-appliance-health.sh}"
URL="${DASHBOARD_URL:-https://bureaublad.dawo.internal}"
# The live USB waits longer (a first Mijn Bureau deployment from a stick takes
# 30-60 minutes, #111); an explicit DASHBOARD_TIMEOUT still wins.
if [ -z "${DASHBOARD_TIMEOUT:-}" ] && [ -r "${DASHBOARD_ENV:-/etc/dawo-appliance/dashboard.env}" ]; then
  # shellcheck disable=SC1090
  . "${DASHBOARD_ENV:-/etc/dawo-appliance/dashboard.env}"
fi
TIMEOUT="${DASHBOARD_TIMEOUT:-1800}"
OPEN_BIN="${DASHBOARD_XDG_OPEN:-xdg-open}"
NOTIFY_BIN="${DASHBOARD_NOTIFY:-notify-send}"
LOG="${DASHBOARD_LOG:-/dev/null}"
# Written by dawo-appliance-guest.service when it deliberately does not start
# the guest (appliance.guest.fitToHost: no /dev/kvm, too little RAM).
GUEST_SKIPPED="${DASHBOARD_GUEST_SKIPPED:-/run/dawo-appliance/guest-skipped}"
GUEST_UNIT="${DASHBOARD_GUEST_UNIT:-dawo-appliance-guest.service}"

# Wait (bounded) until the guest unit has finished, so a deliberate skip is
# known before the long health wait; then say so at once instead of after
# ${TIMEOUT} seconds.
for _ in $(seq 1 60); do
  st="$(systemctl show -p ActiveState --value "${GUEST_UNIT}" 2>/dev/null || echo unknown)"
  [ "${st}" = activating ] || break
  sleep 5
done
if [ -s "${GUEST_SKIPPED}" ]; then
  # No window: the welcome/status window already shows the reason (#106).
  echo "dawo-appliance: the Mijn Bureau guest was not started: $(cat "${GUEST_SKIPPED}")" >&2
  exit 1
fi

# On the live USB Mijn Bureau deploys itself (#111): wait (bounded) until that
# deployment says "klaar" before opening anything, so the browser does not
# show the login while phases 11-14 still run (#143). On "mislukt" or "niet
# mogelijk" stay quiet: the live status page says why. Unset: no wait.
WAIT_STATUS="${DASHBOARD_WAIT_STATUS:-}"
SECONDS=0
if [ -n "${WAIT_STATUS}" ]; then
  while :; do
    s="$(cat "${WAIT_STATUS}" 2>/dev/null || true)"
    case "${s}" in
      klaar*) break ;;
      mislukt* | "niet mogelijk"*)
        echo "dawo-appliance: the Mijn Bureau deployment did not finish (${s}); not opening the dashboard" >&2
        exit 1 ;;
    esac
    if [ "${SECONDS}" -ge "${TIMEOUT}" ]; then
      echo "dawo-appliance: the Mijn Bureau deployment was not done within ${TIMEOUT}s (${s:-no status}); not opening the dashboard" >&2
      exit 1
    fi
    sleep "${DASHBOARD_POLL:-10}"
  done
fi

report=""
rc=0
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

summary="$(printf '%s\n' "${failing}" | head -n 3)"
"${NOTIFY_BIN}" --app-name "DAWO appliance" --icon dialog-warning \
  "Mijn Bureau is nog niet bereikbaar" \
  "${why_nl} De browser is niet geopend. Nog niet in orde:
${summary}
Opnieuw controleren: dawo-appliance-health --once
(English: ${why_en}; the dashboard was not opened.)" \
  >/dev/null 2>&1 || true
exit 1
