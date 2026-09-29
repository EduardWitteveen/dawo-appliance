#!/usr/bin/env bash
#
# DAWO appliance live status page (issue #116).
#
# ONE overview that updates itself: the live USB opens it in the browser at
# login instead of a static welcome window. It shows the login details and,
# per item, what works, what we are waiting for and why: internet, storage on
# the stick, the virtual machine, Mijn Bureau's deployment (with a progress bar
# and the elapsed time) and debug mode. When Mijn Bureau is ready the page
# links to the dashboard (the dashboard opener also opens it).
#
# While Mijn Bureau deploys, the page shows that it is alive (#132): a moving
# indicator, the attempt, how long ago the deployment last wrote to its log,
# and that last line. A failure is a red banner at the top.
#
# Runs as the logged-in user: rewrites the page every STATUS_INTERVAL seconds
# (atomically) until killed; STATUS_ONCE=1 writes it once (offline test,
# tests/test-status-page.sh). Every input can be redirected with STATUS_*.
#
# Experimental and unofficial. Not for production.
# SPDX-License-Identifier: EUPL-1.2

set -uo pipefail

OUT="${STATUS_OUT:-${XDG_RUNTIME_DIR:-/tmp}/dawo-appliance-status.html}"
INTERVAL="${STATUS_INTERVAL:-5}"
PASSWORD_FILE="${STATUS_PASSWORD_FILE:-/var/lib/dawo-appliance/dawo.password.txt}"
GUEST_SKIPPED="${STATUS_GUEST_SKIPPED:-/run/dawo-appliance/guest-skipped}"
GUEST_UNIT="${STATUS_GUEST_UNIT:-dawo-appliance-guest.service}"
DATA_STATUS="${STATUS_DATA:-/run/dawo-appliance/data}"
MB_STATUS="${STATUS_MB:-/run/dawo-appliance/mijnbureau}"
MB_START="${STATUS_MB_START:-/run/dawo-appliance/mijnbureau-start}"
MB_LOG="${STATUS_MB_LOG:-/var/log/dawo-appliance-mijnbureau.log}"
MB_DURATIONS="${STATUS_MB_DURATIONS:-/var/lib/dawo-appliance/mb-durations}"
CMDLINE="${STATUS_CMDLINE:-/proc/cmdline}"
NET_URL="${STATUS_NET_URL:-https://dl.flathub.org/repo/flathub.flatpakrepo}"
CURL_BIN="${STATUS_CURL:-curl}"
SYSTEMCTL_BIN="${STATUS_SYSTEMCTL:-systemctl}"
DASHBOARD="${STATUS_DASHBOARD:-https://bureaublad.dawo.internal}"

esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
now() { date +%s; }
ago() { # ago SECONDS -> "12 s geleden" / "3 min geleden"
  if [ "$1" -lt 90 ]; then echo "$1 s geleden"; else echo "$(( $1 / 60 )) min geleden"; fi
}

# Signs of life from the deployment's log (#132): the attempt (only when it is
# not the first), the time since its last write, and its last non-empty line
# (terminal colour codes removed).
alive() {
  [ -r "${MB_LOG}" ] || return 0
  local attempt age last out=""
  attempt="$(grep -o 'attempt [0-9]' "${MB_LOG}" 2>/dev/null | tail -n 1 | tr -dc '0-9')"
  if [ -n "${attempt}" ] && [ "${attempt}" -gt 1 ]; then out="poging ${attempt} van 3 &middot; "; fi
  age=$(( $(now) - $(stat -c %Y "${MB_LOG}" 2>/dev/null || now) ))
  out="${out}laatste activiteit: $(ago "${age}")"
  last="$(grep -v '^[[:space:]]*$' "${MB_LOG}" 2>/dev/null | tail -n 1 | tr -d '\033' | sed 's/\[[0-9;]*m//g' | cut -c1-140)"
  [ -n "${last}" ] && out="${out}<br><code class='log'>$(esc "${last}")</code>"
  printf '%s' "${out}"
}

# How long phase $1 took the previous time on this machine (#143): the runner
# appends "<phase> <seconds>" to MB_DURATIONS on the stick. Without earlier
# data, the typical duration measured on a Dell Latitude 5550 (2026-09-29).
expected() {
  local n="$1" prev
  prev="$(awk -v n="${n}" '$1 == n { s = $2 } END { if (s != "") print s }' "${MB_DURATIONS}" 2>/dev/null)"
  if [ -n "${prev}" ]; then
    if [ "${prev}" -lt 90 ]; then echo "Vorige keer duurde deze stap op deze laptop ${prev} s"
    else echo "Vorige keer duurde deze stap op deze laptop $(( (prev + 30) / 60 )) min"; fi
    return
  fi
  case "${n}" in
    8) echo "Deze stap duurt meestal ongeveer 6 minuten (alle apps worden gedownload)" ;;
    10) echo "Deze stap duurt meestal 1 tot 2 minuten" ;;
    *) echo "Deze stap duurt meestal minder dan een minuut" ;;
  esac
}

render() {
  local rows="" pw net data guest mb reason mbs n pct elapsed started

  if [ -r "${PASSWORD_FILE}" ]; then pw="$(tr -d '\n' < "${PASSWORD_FILE}")"; else pw="dawo"; fi
  row() { rows="${rows}<tr class='$1'><td class='icon'>$2</td><th>$3</th><td>$4</td></tr>"; }

  if "${CURL_BIN}" -sS -o /dev/null --max-time 4 "${NET_URL}" >/dev/null 2>&1; then
    row ok "&#10004;" "Internet" "verbonden"; net="yes"
  else
    row wait "&#8987;" "Internet" "nog geen verbinding. Verbind met de wifi <b>Dawo</b> (wachtwoord
    <code>DawoDawo</code>), een ander netwerk (icoon rechtsonder) of een netwerkkabel. Zonder internet
    kan Mijn Bureau niet worden uitgerold."; net="no"
  fi

  data="$(cat "${DATA_STATUS}" 2>/dev/null || true)"
  case "${data}" in
    stick:*) row ok "&#10004;" "Opslag" "op de USB-stick, blijft bewaard" ;;
    ram:*) row warn "&#9888;" "Opslag" "alleen in het werkgeheugen, weg na afsluiten: $(esc "${data#ram: }")" ;;
    *) row wait "&#8987;" "Opslag" "wordt voorbereid" ;;
  esac

  if [ -s "${GUEST_SKIPPED}" ]; then
    reason="$(cat "${GUEST_SKIPPED}")"
    case "${reason}" in
      "no /dev/kvm"*) reason="hardwarevirtualisatie (VT-x/AMD-V) staat uit in de BIOS, of deze machine is zelf een virtuele machine" ;;
      "not enough memory"*) reason="te weinig geheugen (ongeveer 9 GB of meer nodig)" ;;
    esac
    row warn "&#9888;" "Virtuele machine" "niet gestart: $(esc "${reason}"). De werkplek zelf werkt gewoon."
    guest="skipped"
  else
    local st res
    st="$("${SYSTEMCTL_BIN}" show -p ActiveState --value "${GUEST_UNIT}" 2>/dev/null || echo unknown)"
    res="$("${SYSTEMCTL_BIN}" show -p Result --value "${GUEST_UNIT}" 2>/dev/null || echo unknown)"
    if [ "${st}" = activating ]; then
      row wait "&#8987;" "Virtuele machine" "wordt gestart"
    elif [ "${res}" = success ]; then
      row ok "&#10004;" "Virtuele machine" "gestart (Ubuntu met K3s)"
    else
      row warn "&#9888;" "Virtuele machine" "kon niet starten ($(esc "${res}")); zie de logs op de USB-stick"
    fi
    guest="yes"
  fi

  mbs="$(cat "${MB_STATUS}" 2>/dev/null || true)"
  case "${mbs}" in
    "klaar"*) row ok "&#10004;" "Mijn Bureau" "uitgerold. <a class='btn' href='${DASHBOARD}'>Open Mijn Bureau</a>
      <br>Inloggen met een van de demo-accounts: <b>johndoe</b> of <b>janedoe</b>, wachtwoord
      <code>myStrongPassword123</code>."; mb="done" ;;
    "mislukt"*) row fail "&#10008;" "Mijn Bureau" "$(esc "${mbs}")<br><small>De uitrol is gestopt. Start de laptop
      opnieuw op om het nog eens te proberen; hij gaat dan verder waar hij was.</small>"; mb="failed" ;;
    "niet mogelijk"*) row warn "&#9888;" "Mijn Bureau" "$(esc "${mbs}")"; mb="no" ;;
    *"stap "*" van "*)
      n="$(printf '%s' "${mbs}" | sed -n 's/.*stap \([0-9]*\) van \([0-9]*\).*/\1/p')"
      pct=$(( (${n:-1} - 1) * 100 / 14 ))
      elapsed=""
      if started="$(cat "${MB_START}" 2>/dev/null)" && [ -n "${started}" ]; then
        elapsed=" &middot; bezig: $(( ($(now) - started) / 60 )) min"
      fi
      row wait "<span class='spin'></span>" "Mijn Bureau" "$(esc "${mbs}")${elapsed}<div class='bar'><div style='width:${pct}%'></div></div>
      <small>$(expected "${n:-0}"). $(alive)</small><br>
      <small>De eerste keer 30 tot 60 minuten (apps downloaden); daarna opent het dashboard vanzelf.</small>"
      mb="busy" ;;
    "") if [ "${guest}" = skipped ]; then
          row warn "&#9888;" "Mijn Bureau" "kan niet worden uitgerold zonder virtuele machine"; mb="no"
        else
          row wait "&#8987;" "Mijn Bureau" "wacht op de virtuele machine$([ "${net}" = no ] && echo " en internet")"; mb="wait"
        fi ;;
    *) row wait "<span class='spin'></span>" "Mijn Bureau" "$(esc "${mbs}")"; mb="wait" ;;
  esac

  if ! grep -qw 'dawo.debug=0' "${CMDLINE}" 2>/dev/null; then
    row warn "&#9888;" "Debug-modus" "aan: elke 30 seconden een schermafbeelding en de logs naar de USB-stick
    <code>DAWO_LOGS</code>, voor de ontwikkelaars (ook Claude, de AI-assistent). Alleen voor testen."
  fi

  local summary="Even geduld: er wordt nog iets voorbereid." state="bezig" banner="sub"
  case "${mb}" in
    busy) summary="Bezig: Mijn Bureau wordt uitgerold." ;;
    done) summary="Mijn Bureau staat klaar."; state="klaar" ;;
    failed) summary="Er ging iets mis: de uitrol van Mijn Bureau is gestopt. De details staan op de USB-stick."
            state="mislukt"; banner="sub banner-fail" ;;
    no) summary="De DAWO-werkplek werkt; Mijn Bureau kan op deze machine niet draaien."; state="beperkt" ;;
  esac

  cat > "${OUT}.new" <<HTML
<!doctype html><html lang="nl"><head><meta charset="utf-8">
<meta http-equiv="refresh" content="${INTERVAL}">
<title>DAWO appliance &mdash; ${state}</title>
<style>
 body{font-family:system-ui,sans-serif;margin:2em auto;max-width:52em;color:#1d2b3a;background:#f4f7fb}
 h1{font-size:1.5em;margin-bottom:.2em} .sub{color:#555;margin-top:0}
 .banner-fail{background:#ffebe9;border:1px solid #cf222e;color:#82071e;padding:.7em .9em;border-radius:6px}
 table{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;box-shadow:0 1px 3px #0002}
 td,th{padding:.7em .8em;text-align:left;vertical-align:top;border-bottom:1px solid #eee}
 th{width:10em} .icon{width:1.5em;font-size:1.2em} .ok .icon{color:#1a7f37} .warn .icon{color:#b35900} .wait .icon{color:#0969da}
 .fail{background:#fff5f5} .fail .icon{color:#cf222e}
 .bar{height:.7em;background:#e5e9f0;border-radius:4px;margin:.5em 0} .bar div{height:100%;background:#0969da;border-radius:4px}
 .spin{display:inline-block;width:.9em;height:.9em;border:.18em solid #cfe0f5;border-top-color:#0969da;border-radius:50%;animation:spin 1s linear infinite}
 @keyframes spin{to{transform:rotate(360deg)}}
 code.log{display:inline-block;max-width:100%;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;color:#555;background:#f1f3f5}
 .btn{display:inline-block;margin-left:.5em;padding:.3em .8em;background:#1a7f37;color:#fff;border-radius:4px;text-decoration:none}
 .note{margin-top:1.5em;font-size:.9em;color:#555} code{background:#eef;padding:0 .2em}
</style></head><body>
<h1>DAWO appliance &mdash; status</h1>
<p class="${banner}"><b>${summary}</b> Deze pagina ververst zichzelf.</p>
<p>Ingelogd als <b>dawo</b> &middot; wachtwoord (beheer): <code>$(esc "${pw}")</code></p>
<table>${rows}</table>
<p class="note"><b>Experimenteel, onofficieel, niet voor productie.</b> Wachtwoorden staan leesbaar
op deze machine; er is geen schijfversleuteling. Laatst bijgewerkt: $(date +%H:%M:%S).<br>
<small>English: experimental, unofficial demo, not for production. This page shows what works and what
we are waiting for, and updates itself.</small></p>
</body></html>
HTML
  mv -f "${OUT}.new" "${OUT}"
}

render
[ "${STATUS_ONCE:-0}" = 1 ] && exit 0
while sleep "${INTERVAL}"; do render; done
