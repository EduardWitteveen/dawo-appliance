#!/usr/bin/env bash
#
# Offline test for health/dawo-appliance-health.sh and
# health/dawo-appliance-open-dashboard.sh. Requires no Nix, no root, no
# network and no VM: every external command (ssh, curl, resolvectl, ping,
# xdg-open, kdialog) is a fake under a temp dir, selected through HEALTH_* /
# DASHBOARD_* environment variables. Runs on Linux, WSL and Windows Git Bash
# (bash 4+, awk, sed, and Python 3 for the JSON assertions — `python3`, or
# `python` as Windows Git Bash ships it).
#
# Scenarios (FAKE_SCENARIO, read by the fakes):
#   ok               everything healthy
#   certs-pending    one Certificate never becomes Ready
#   issuer-mismatch  Keycloak answers with another issuer
#   flip             Certificates become Ready after the second poll
#   dns-wrong        the name resolves to the wrong address
#
# Asserts:
#   1. ok:  --once --json exits 0, "healthy": true, every check "ok": true
#   2. ok:  --once prints only OK lines
#   3. certs-pending: --once exits 1, WAIT on the certificates line, rest OK
#   4. issuer-mismatch: --once exits 1, FAIL on the https_oidc line naming the issuer
#   5. flip: --wait exits 0 and needed >= 4 certificate polls
#      (two pending + three equal all-Ready polls, as upstream's wait_for_certs)
#   6. certs-pending: --wait --timeout 1 exits 1 and reports the WAIT line
#   7. dns-wrong: FAIL on the dns line
#   8. open-dashboard (ok): opens the dashboard URL with the fake xdg-open, no dialog
#   9. open-dashboard (certs-pending, timeout 1): no browser, kdialog names the check
#  10. curl was always called with --cacert <CA>

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEALTH="${REPO_ROOT}/health/dawo-appliance-health.sh"
OPENER="${REPO_ROOT}/health/dawo-appliance-open-dashboard.sh"

pass=0
fail=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
show() { printf '%s\n' "$1" | sed 's/^/      | /'; }

echo "test-health-check: starting"
[[ -f "${HEALTH}" ]] || { echo "health script not found: ${HEALTH}"; exit 2; }
[[ -f "${OPENER}" ]] || { echo "open-dashboard script not found: ${OPENER}"; exit 2; }
# Windows Git Bash usually ships `python` (3.x) without a `python3` alias.
PY="$(command -v python3 || command -v python || true)"
if [[ -z "${PY}" ]] || ! "${PY}" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)'; then
  echo "python 3 is required for the JSON assertions (looked for python3, python)"; exit 2
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/dawo-health-test.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT
fakes="${tmp}/bin"
state="${tmp}/state"
mkdir -p "${fakes}" "${state}"

# --- fixtures: CA, ssh key, Firefox policy -----------------------------------
ca="${tmp}/ca.crt"
printf -- '-----BEGIN CERTIFICATE-----\nMIIBfakeDAWOapplianceCA\n-----END CERTIFICATE-----\n' >"${ca}"
key="${tmp}/id_ed25519"
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nfake\n-----END OPENSSH PRIVATE KEY-----\n' >"${key}"
policy="${tmp}/policies.json"
printf '{"policies": {"Certificates": {"Install": ["%s"]}}}\n' "${ca}" >"${policy}"

# --- fakes -------------------------------------------------------------------
# ssh: the remote command is the last argument; options are ignored.
cat >"${fakes}/ssh" <<'EOF'
#!/usr/bin/env bash
set -u
cmd="${*: -1}"
scenario="${FAKE_SCENARIO:-ok}"
state="${FAKE_STATE:?}"
printf '%s\n' "${cmd}" >>"${state}/ssh.log"
cert_lines() {
  # cert_lines READY1 READY2 READY3 — NAMESPACE NAME READY SECRET AGE
  printf 'mb-keycloak   id-dawo-internal-tls           %s   id-dawo-internal-tls           9m\n' "$1"
  printf 'mb-bureaublad bureaublad-dawo-internal-tls   %s   bureaublad-dawo-internal-tls   9m\n' "$2"
  printf 'mb-grist      grist-dawo-internal-tls        %s   grist-dawo-internal-tls        9m\n' "$3"
}
case "${cmd}" in
  true) exit 0 ;;
  *"get node"*)
    echo "dawo-appliance-mb   Ready   control-plane,master   14m   v1.36.4+k3s1" ;;
  *"get clusterissuer"*)
    echo "dawo-appliance-ca   True    Signing CA verified   12m" ;;
  *"get certificate"*"custom-columns"*)
    printf 'ClusterIssuer   dawo-appliance-ca\n%.0s' 1 2 3 ;;
  *"get certificate"*)
    n=$(( $(cat "${state}/certpolls" 2>/dev/null || echo 0) + 1 ))
    echo "${n}" >"${state}/certpolls"
    case "${scenario}" in
      certs-pending) cert_lines True True False ;;
      flip) if [ "${n}" -le 2 ]; then cert_lines True False True; else cert_lines True True True; fi ;;
      *) cert_lines True True True ;;
    esac ;;
  *) echo "fake ssh: unexpected command: ${cmd}" >&2; exit 255 ;;
esac
EOF

# curl: understands --output FILE, --write-out FMT, --cacert FILE; URL is the
# last argument. Logs the cacert it was given.
cat >"${fakes}/curl" <<'EOF'
#!/usr/bin/env bash
set -u
scenario="${FAKE_SCENARIO:-ok}"
state="${FAKE_STATE:?}"
out=""; cacert=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output) shift; out="$1" ;;
    --cacert) shift; cacert="$1" ;;
    --write-out | --max-time) shift ;;
    -*) ;;
    *) url="$1" ;;
  esac
  shift
done
printf '%s %s\n' "${cacert:-NONE}" "${url}" >>"${state}/curl.log"
case "${url}" in
  *"/.well-known/openid-configuration")
    issuer="https://id.dawo.internal/realms/mijnbureau"
    [ "${scenario}" = "issuer-mismatch" ] && issuer="https://id.example.org/realms/mijnbureau"
    printf '{"issuer":"%s","authorization_endpoint":"%s/protocol/openid-connect/auth"}\n' "${issuer}" "${issuer}" >"${out}"
    printf '200' ;;
  *)
    printf '<!doctype html><title>Bureaublad</title>\n' >"${out}"
    printf '200' ;;
esac
EOF

cat >"${fakes}/resolvectl" <<'EOF'
#!/usr/bin/env bash
addr="192.168.150.10"
[ "${FAKE_SCENARIO:-ok}" = "dns-wrong" ] && addr="192.168.122.57"
printf '%s: %s                       -- link: virbr0\n\n-- Information acquired via protocol DNS in 1.3ms.\n' "$2" "${addr}"
EOF

cat >"${fakes}/ping" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"${fakes}/xdg-open" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"${FAKE_STATE:?}/xdg-open.log"
EOF

cat >"${fakes}/kdialog" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FAKE_STATE:?}/kdialog.log"
EOF

chmod +x "${fakes}"/*

reset_state() { rm -f "${state}"/*; }

# Common environment for the health script.
export HEALTH_SSH="${fakes}/ssh"
export HEALTH_CURL="${fakes}/curl"
export HEALTH_RESOLVE="${fakes}/resolvectl"
export HEALTH_GETENT="${fakes}/getent-missing"
export HEALTH_PING="${fakes}/ping"
export HEALTH_CA_CERT="${ca}"
export HEALTH_CA_ENV="${tmp}/no-ca.env"
export HEALTH_SSH_KEY="${key}"
export HEALTH_FIREFOX_POLICY="${policy}"
export HEALTH_CERT_SETTLE=0
export HEALTH_POLL_INTERVAL=0.2
export FAKE_STATE="${state}"

run_health() { bash "${HEALTH}" "$@"; }

# --- 1. all OK: --once --json ------------------------------------------------
reset_state
export FAKE_SCENARIO=ok
rc=0
out="$(run_health --once --json 2>"${tmp}/stderr")" || rc=$?
if [ "${rc}" -eq 0 ] && printf '%s' "${out}" | "${PY}" -c '
import json, sys
d = json.load(sys.stdin)
checks = d["checks"]
assert d["healthy"] is True, d
assert len(checks) == 9, list(checks)
assert all(c["ok"] is True and c["status"] == "OK" for c in checks.values()), checks
for name in ("dns", "guest", "node", "clusterissuer", "certificates", "cert_issuers", "https_dashboard", "https_oidc", "browser_trust"):
    assert name in checks, name
'; then
  ok "ok scenario: --once --json exits 0, healthy, all 9 checks ok=true"
else
  bad "ok scenario: --once --json (rc=${rc})"
  show "${out}"; show "$(cat "${tmp}/stderr")"
fi

# --- 2. all OK: human report -------------------------------------------------
reset_state
rc=0
out="$(run_health --once 2>&1)" || rc=$?
if [ "${rc}" -eq 0 ] && [ "$(printf '%s\n' "${out}" | grep -c '^OK ')" -eq 9 ] \
   && ! printf '%s\n' "${out}" | grep -Eq '^(WAIT|FAIL)'; then
  ok "ok scenario: --once prints 9 OK lines and nothing else"
else
  bad "ok scenario: --once human report (rc=${rc})"; show "${out}"
fi

# --- 3. certificates pending -------------------------------------------------
reset_state
export FAKE_SCENARIO=certs-pending
rc=0
out="$(run_health --once 2>&1)" || rc=$?
if [ "${rc}" -eq 1 ] \
   && printf '%s\n' "${out}" | grep -Eq '^WAIT +certificates +2/3 Certificates Ready' \
   && [ "$(printf '%s\n' "${out}" | grep -c '^OK ')" -eq 8 ]; then
  ok "certs-pending: --once exits 1 with WAIT on certificates (2/3), the other 8 OK"
else
  bad "certs-pending: --once (rc=${rc})"; show "${out}"
fi

# --- 4. issuer mismatch ------------------------------------------------------
reset_state
export FAKE_SCENARIO=issuer-mismatch
rc=0
out="$(run_health --once 2>&1)" || rc=$?
if [ "${rc}" -eq 1 ] \
   && printf '%s\n' "${out}" | grep -Eq "^FAIL +https_oidc +.*id.example.org.*expected 'https://id.dawo.internal/realms/mijnbureau'"; then
  ok "issuer-mismatch: --once exits 1 with FAIL on https_oidc naming both issuers"
else
  bad "issuer-mismatch: --once (rc=${rc})"; show "${out}"
fi

# --- 5. flip: --wait succeeds once the certificates settle -------------------
reset_state
export FAKE_SCENARIO=flip
rc=0
# The timeout is a generous upper bound, not the thing under test: the
# assertion is the poll count and the exit code. Keep it well above the time
# four polls need on the slowest supported host (Git Bash on Windows spawns
# the fakes far slower than Linux), or this test goes flaky by machine speed.
out="$(run_health --wait --timeout 60 2>"${tmp}/stderr")" || rc=$?
polls="$(cat "${state}/certpolls" 2>/dev/null || echo 0)"
if [ "${rc}" -eq 0 ] && [ "${polls}" -ge 4 ] \
   && printf '%s\n' "${out}" | grep -Eq '^OK +certificates +3/3 Certificates Ready, count stable' \
   && grep -q 'all 9 checks OK' "${tmp}/stderr" \
   && grep -q 'certificates (WAIT: 2/3' "${tmp}/stderr"; then
  ok "flip: --wait exits 0 after ${polls} certificate polls, progress shows the WAIT"
else
  bad "flip: --wait --timeout 3 (rc=${rc}, polls=${polls})"
  show "${out}"; show "$(cat "${tmp}/stderr")"
fi

# --- 6. certs pending: --wait times out ---------------------------------------
reset_state
export FAKE_SCENARIO=certs-pending
rc=0
out="$(run_health --wait --timeout 1 2>"${tmp}/stderr")" || rc=$?
if [ "${rc}" -eq 1 ] \
   && printf '%s\n' "${out}" | grep -Eq '^WAIT +certificates' \
   && grep -q 'timeout after 1s' "${tmp}/stderr"; then
  ok "certs-pending: --wait --timeout 1 exits 1, final report keeps the WAIT line"
else
  bad "certs-pending: --wait --timeout 1 (rc=${rc})"
  show "${out}"; show "$(cat "${tmp}/stderr")"
fi

# --- 7. dns resolves to the wrong address ------------------------------------
reset_state
export FAKE_SCENARIO=dns-wrong
rc=0
out="$(run_health --once 2>&1)" || rc=$?
if [ "${rc}" -eq 1 ] \
   && printf '%s\n' "${out}" | grep -Eq '^FAIL +dns +.*192\.168\.122\.57, expected the VM at 192\.168\.150\.10'; then
  ok "dns-wrong: FAIL on dns with both addresses"
else
  bad "dns-wrong: --once (rc=${rc})"; show "${out}"
fi

# --- 8. open-dashboard: healthy -> browser ------------------------------------
reset_state
export FAKE_SCENARIO=ok
export DASHBOARD_XDG_OPEN="${fakes}/xdg-open"
export DASHBOARD_KDIALOG="${fakes}/kdialog"
export DASHBOARD_LOG="${tmp}/dashboard.log"
rc=0
out="$(bash "${OPENER}" 2>&1)" || rc=$?
if [ "${rc}" -eq 0 ] \
   && [ "$(cat "${state}/xdg-open.log" 2>/dev/null)" = "https://bureaublad.dawo.internal" ] \
   && [ ! -e "${state}/kdialog.log" ]; then
  ok "open-dashboard: healthy -> xdg-open https://bureaublad.dawo.internal, no dialog"
else
  bad "open-dashboard healthy (rc=${rc})"; show "${out}"
fi

# --- 9. open-dashboard: unhealthy -> dialog, no browser ----------------------
reset_state
export FAKE_SCENARIO=certs-pending
export DASHBOARD_TIMEOUT=1
rc=0
out="$(bash "${OPENER}" 2>&1)" || rc=$?
if [ "${rc}" -eq 1 ] && [ ! -e "${state}/xdg-open.log" ] \
   && grep -q -- '--sorry' "${state}/kdialog.log" 2>/dev/null \
   && grep -q 'WAIT certificates' "${state}/kdialog.log"; then
  ok "open-dashboard: unhealthy -> kdialog names the WAIT check, browser not opened"
else
  bad "open-dashboard unhealthy (rc=${rc})"; show "${out}"; show "$(cat "${state}/kdialog.log" 2>/dev/null)"
fi
unset DASHBOARD_TIMEOUT

# --- 10. curl always got the CA ------------------------------------------------
reset_state
export FAKE_SCENARIO=ok
run_health --once >/dev/null 2>&1 || true
if [ -s "${state}/curl.log" ] && ! grep -qv "^${ca} https://" "${state}/curl.log"; then
  ok "every curl call used --cacert ${ca##*/}"
else
  bad "curl calls without the CA"; show "$(cat "${state}/curl.log" 2>/dev/null)"
fi

echo
echo "test-health-check: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
