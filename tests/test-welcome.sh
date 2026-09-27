#!/usr/bin/env bash
# Offline test for health/dawo-appliance-welcome.sh (issue #106): the ONE
# welcome/status window at login. curl, systemctl and kdialog are fakes; no
# network, no root, no Nix. Runs on Linux, WSL and Windows Git Bash.
#
#   1. online, guest started, installed appliance: one window, internet OK,
#      guest started, no debug line
#   2. offline, guest skipped, live USB in debug mode: internet warning with
#      the demo Wi-Fi, the skip reason, the debug-mode line
#   3. live USB booted with dawo.debug=0: no debug line
#   4. a generated password is shown, HTML-escaped
#
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WELCOME="${REPO_ROOT}/health/dawo-appliance-welcome.sh"
[[ -f "${WELCOME}" ]] || { echo "welcome script not found: ${WELCOME}"; exit 2; }

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
# systemctl show -p <Prop> --value <unit>
case "$3" in
  ActiveState) echo "${FAKE_GUEST_STATE:-inactive}" ;;
  Result) echo "${FAKE_GUEST_RESULT:-success}" ;;
esac
EOF
cat >"${fakes}/kdialog" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FAKE_DIALOG:?}"
EOF
chmod +x "${fakes}"/*

pass=0
fail=0
ok() { echo "  PASS $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL $*"; fail=$((fail + 1)); }

export WELCOME_CURL="${fakes}/curl"
export WELCOME_SYSTEMCTL="${fakes}/systemctl"
export WELCOME_KDIALOG="${fakes}/kdialog"
export WELCOME_WAIT=0
export WELCOME_STEP=1

run() {
  export FAKE_DIALOG="${tmp}/dialog.$1"
  : >"${FAKE_DIALOG}"
  bash "${WELCOME}"
}

# 1. online, guest started, installed appliance.
printf 'quiet\n' >"${tmp}/cmdline"
export WELCOME_CMDLINE="${tmp}/cmdline"
export WELCOME_LIVE_MARKER="${tmp}/no-live-marker"
export WELCOME_GUEST_SKIPPED="${tmp}/no-skip"
export WELCOME_PASSWORD_FILE="${tmp}/no-password"
FAKE_NET=up FAKE_GUEST_STATE=inactive FAKE_GUEST_RESULT=success run 1
d="${tmp}/dialog.1"
if [ "$(grep -c -- '--msgbox' "$d")" = 1 ] && grep -q 'verbonden' "$d" \
   && grep -q 'gestart (Ubuntu met K3s)' "$d" && ! grep -q 'Debug-modus' "$d" \
   && grep -q '<tt>dawo</tt>' "$d"; then
  ok "online + guest started: one window, internet OK, guest started, no debug line"
else
  bad "online + guest started"; cat "$d"
fi

# 2. offline, guest skipped, live USB in debug mode.
printf 'no /dev/kvm: virtualisation is off\n' >"${tmp}/skip"
: >"${tmp}/live"
export WELCOME_GUEST_SKIPPED="${tmp}/skip"
export WELCOME_LIVE_MARKER="${tmp}/live"
SECONDS=0
FAKE_NET=down run 2
d="${tmp}/dialog.2"
if [ "$(grep -c -- '--msgbox' "$d")" = 1 ] && grep -q 'geen verbinding' "$d" \
   && grep -q 'DawoDawo' "$d" && grep -q 'niet gestart: hardwarevirtualisatie' "$d" \
   && grep -q 'Debug-modus' "$d" && [ "${SECONDS}" -lt 20 ]; then
  ok "offline + guest skipped + live debug: internet warning with demo Wi-Fi, skip reason, debug line"
else
  bad "offline + guest skipped + live debug (${SECONDS}s)"; cat "$d"
fi

# 2b. too little memory: Dutch reason with the amount.
printf 'not enough memory: this machine has 7803 MiB; the guest needs at least 3 GiB next to 6144 MiB for the desktop
' >"${tmp}/skip"
FAKE_NET=up run 2b
d="${tmp}/dialog.2b"
if grep -q 'te weinig geheugen (7803 MiB)' "$d"; then
  ok "guest skipped for memory: Dutch reason with the amount"
else
  bad "guest skipped for memory"; cat "$d"
fi
printf 'no /dev/kvm: virtualisation is off
' >"${tmp}/skip"

# 3. live USB booted with dawo.debug=0.
printf 'quiet dawo.debug=0\n' >"${tmp}/cmdline"
FAKE_NET=up run 3
d="${tmp}/dialog.3"
if ! grep -q 'Debug-modus' "$d" && grep -q 'verbonden' "$d"; then
  ok "live USB with dawo.debug=0: no debug line"
else
  bad "live USB with dawo.debug=0"; cat "$d"
fi

# 4. a generated password is shown, HTML-escaped.
printf 'a<b&c\n' >"${tmp}/password"
export WELCOME_PASSWORD_FILE="${tmp}/password"
FAKE_NET=up run 4
d="${tmp}/dialog.4"
if grep -q '<tt>a&lt;b&amp;c</tt>' "$d"; then
  ok "generated password shown and HTML-escaped"
else
  bad "generated password"; cat "$d"
fi

echo
echo "test-welcome: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
