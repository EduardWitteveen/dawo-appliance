#!/usr/bin/env bash
#
# DAWO appliance welcome and status window (issue #106).
#
# ONE window at login instead of several (maintainer, 2026-09-27): login
# details, then a checklist of what works and what not, with the reason and
# what to do. It waits briefly (WELCOME_WAIT, default 30 s) so the guest and
# network state are known when it is shown. Anything that happens later is
# reported as a desktop notification (they stack in the notification area),
# not as another window.
#
# Checks:
#   - internet: can the appliance reach the online sources it needs (DAWO's
#     app installs; later the Mijn Bureau deploy)? If not: why that matters
#     and how to fix it (the demo Wi-Fi "Dawo", or a cable).
#   - virtual machine: started, or skipped with the reason
#     (/run/dawo-appliance/guest-skipped, written by dawo-appliance-guest).
#   - Mijn Bureau: honest state (the deploy is not wired yet, issue #8).
#   - debug mode (live USB only): logs and screenshots go to a DAWO_LOGS stick.
#
# Every input can be redirected for the offline test (tests/test-welcome.sh).
#
# Experimental and unofficial. Not for production.
# SPDX-License-Identifier: EUPL-1.2

set -uo pipefail

PASSWORD_FILE="${WELCOME_PASSWORD_FILE:-/var/lib/dawo-appliance/dawo.password.txt}"
GUEST_SKIPPED="${WELCOME_GUEST_SKIPPED:-/run/dawo-appliance/guest-skipped}"
GUEST_UNIT="${WELCOME_GUEST_UNIT:-dawo-appliance-guest.service}"
CMDLINE="${WELCOME_CMDLINE:-/proc/cmdline}"
LIVE_MARKER="${WELCOME_LIVE_MARKER:-/etc/dawo-appliance/live}"
NET_URL="${WELCOME_NET_URL:-https://dl.flathub.org/repo/flathub.flatpakrepo}"
CURL_BIN="${WELCOME_CURL:-curl}"
SYSTEMCTL_BIN="${WELCOME_SYSTEMCTL:-systemctl}"
KDIALOG_BIN="${WELCOME_KDIALOG:-kdialog}"
WAIT="${WELCOME_WAIT:-30}"
STEP="${WELCOME_STEP:-3}"

esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

internet_ok() {
  "${CURL_BIN}" -sS -o /dev/null --max-time 5 "${NET_URL}" >/dev/null 2>&1
}

guest_settled() {
  local st
  st="$("${SYSTEMCTL_BIN}" show -p ActiveState --value "${GUEST_UNIT}" 2>/dev/null || echo unknown)"
  [ "${st}" != activating ]
}

# Wait (bounded) until the guest unit has decided and the network is up.
net=no
waited=0
while :; do
  internet_ok && net=yes
  if guest_settled && [ "${net}" = yes ]; then break; fi
  [ "${waited}" -ge "${WAIT}" ] && break
  sleep "${STEP}"
  waited=$((waited + STEP))
done

if [ -r "${PASSWORD_FILE}" ]; then
  pw="$(tr -d '\n' < "${PASSWORD_FILE}")"
else
  pw="dawo"
fi

ok="&#10004;"   # check mark
warn="&#9888;"  # warning sign
rows=""
row() { rows="${rows}<tr><td valign='top'>$1</td><td valign='top'><b>$2</b></td><td>$3</td></tr>"; }

if [ "${net}" = yes ]; then
  row "${ok}" "Internet" "verbonden"
else
  row "${warn}" "Internet" "geen verbinding. Zonder internet worden de apps van de werkplek niet
geïnstalleerd en kan Mijn Bureau niet worden uitgerold. Verbind met de wifi <b>Dawo</b>
(wachtwoord <tt>DawoDawo</tt>), een ander netwerk (icoon rechtsonder) of een netwerkkabel."
fi

if [ -s "${GUEST_SKIPPED}" ]; then
  row "${warn}" "Virtuele machine" "niet gestart: $(esc "$(cat "${GUEST_SKIPPED}")")"
else
  result="$("${SYSTEMCTL_BIN}" show -p Result --value "${GUEST_UNIT}" 2>/dev/null || echo unknown)"
  state="$("${SYSTEMCTL_BIN}" show -p ActiveState --value "${GUEST_UNIT}" 2>/dev/null || echo unknown)"
  if [ "${result}" = success ] && [ "${state}" != activating ]; then
    row "${ok}" "Virtuele machine" "gestart (Ubuntu met K3s)"
  elif [ "${state}" = activating ]; then
    row "${warn}" "Virtuele machine" "wordt nog gestart"
  else
    row "${warn}" "Virtuele machine" "kon niet starten (${result}); zie het systeemlogboek"
  fi
fi

row "${warn}" "Mijn Bureau" "wordt in deze versie nog niet automatisch uitgerold (in ontwikkeling)"

debug_html=""
if [ -e "${LIVE_MARKER}" ] && ! grep -qw 'dawo.debug=0' "${CMDLINE}" 2>/dev/null; then
  row "${warn}" "Debug-modus" "aan (voorlopig standaard): elke 30 seconden een schermafbeelding en
de systeemlogs gaan naar een USB-stick <tt>DAWO_LOGS</tt>, zodat de ontwikkelaars (ook Claude,
de AI-assistent van dit project) kunnen debuggen. Alles op het scherm, ook wachtwoorden, komt op
die stick. Niet voor definitief gebruik."
  debug_html=" Debug mode is on: screenshots and logs go to a DAWO_LOGS USB stick."
fi

"${KDIALOG_BIN}" \
  --title "DAWO appliance (experimenteel / experimental)" \
  --icon computer \
  --msgbox "<h3>Welkom bij de DAWO appliance</h3>
<p>Een <b>experimentele, onofficiële demo-machine</b>: de DAWO-werkplek (zoals in de
pilots) met daarnaast een virtuele machine voor Mijn Bureau.</p>
<p><b>Ingelogd als:</b> dawo &nbsp; <b>Wachtwoord</b> (schermslot, beheertaken): <tt>$(esc "${pw}")</tt></p>
<table cellspacing='4'>${rows}</table>
<p><b>Niet voor productie.</b> Wachtwoorden staan leesbaar op deze machine en op het
scherm; er is geen schijfversleuteling.</p>
<hr/>
<p><small>English: experimental, unofficial demo; logged in as <b>dawo</b>, password
<tt>$(esc "${pw}")</tt>; not for production. The list above shows internet, virtual machine
and Mijn Bureau status.${debug_html}</small></p>" \
  >/dev/null 2>&1 || true
