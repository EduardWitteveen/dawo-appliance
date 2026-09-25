#!/usr/bin/env bash
#
# dawo-appliance-health.sh — local health check for the Mijn Bureau deployment.
#
# Runs on the appliance HOST (the NixOS/DAWO machine) and decides whether the
# demo is ready for a browser: name resolution to the VM, the guest and its K3s
# node, cert-manager (ClusterIssuer and every Certificate), HTTPS through the
# appliance CA on the dashboard and on Keycloak's OIDC discovery document, and
# the browser trust for the CA. The criteria are those of ADR 0004
# ("Health check (Slice 7) gates the browser"); the certificate wait mirrors
# `wait_for_certs` in mijn-bureau-infra scripts/single-vps-deploy/install.sh
# (rev b2ae545): all Certificates Ready AND an unchanged count over
# consecutive polls, so we do not declare victory before every Certificate
# resource has been created.
#
# Modes
#   --once              run every check once, print the report, exit 0 (all OK)
#                       or 1 (default)
#   --wait              poll until every check is OK or --timeout expires
#                       (progress on stderr, final report on stdout)
#   --timeout SECONDS   for --wait (default 1800)
#   --interval SECONDS  poll interval for --wait (default 15, like upstream)
#   --json              print the final report as JSON on stdout (the human
#                       report then goes to stderr)
#
# Each check prints one line:  OK|WAIT|FAIL  <check>  <reason>
#   OK    the criterion holds
#   WAIT  not there yet; expected to resolve by itself (deployment in progress)
#   FAIL  needs attention; waiting will not fix it (wrong address, untrusted
#         certificate, wrong OIDC issuer, missing policy file, ...).
#         --wait keeps polling on FAIL as well, since early-boot states can
#         look like a FAIL for one poll; the final report says what remained.
#
# Exit codes: 0 healthy, 1 not (yet) healthy or timed out, 2 usage error.
#
# Contracts this script relies on (provided by other slices, see health/README.md):
#   - guest reachable as ops@192.168.150.10 with key /var/lib/dawo-appliance/ssh/id_ed25519
#     and `k3s kubectl` on its PATH
#   - CA certificate at /var/lib/dawo-appliance/ca/ca.crt (or /etc/dawo-appliance/ca.env)
#   - host resolves *.dawo.internal to the VM (systemd-resolved routing domain)
#
# Every external command and every path is overridable through the environment
# (HEALTH_*), so the logic is testable offline with fake commands
# (tests/test-health-check.sh). Nothing here writes anywhere except a temp dir.
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (all optional)
# ---------------------------------------------------------------------------
CA_ENV="${HEALTH_CA_ENV:-/etc/dawo-appliance/ca.env}"
if [ -z "${HEALTH_CA_CERT:-}" ] && [ -r "${CA_ENV}" ]; then
  # shellcheck disable=SC1090  # run-time file written by hosts/appliance/appliance-ca.nix
  . "${CA_ENV}"
fi

BASE_DOMAIN="${HEALTH_BASE_DOMAIN:-dawo.internal}"
DASHBOARD_HOST="${HEALTH_DASHBOARD_HOST:-bureaublad.${BASE_DOMAIN}}"
ID_HOST="${HEALTH_ID_HOST:-id.${BASE_DOMAIN}}"
REALM="${HEALTH_REALM:-mijnbureau}"
DASHBOARD_URL="${HEALTH_DASHBOARD_URL:-https://${DASHBOARD_HOST}/}"
OIDC_URL="${HEALTH_OIDC_URL:-https://${ID_HOST}/realms/${REALM}/.well-known/openid-configuration}"
EXPECTED_ISSUER="${HEALTH_EXPECTED_ISSUER:-https://${ID_HOST}/realms/${REALM}}"

VM_IP="${HEALTH_VM_IP:-192.168.150.10}"
VM_USER="${HEALTH_VM_USER:-ops}"
SSH_KEY="${HEALTH_SSH_KEY:-/var/lib/dawo-appliance/ssh/id_ed25519}"
SSH_TIMEOUT="${HEALTH_SSH_TIMEOUT:-5}"
KUBECTL="${HEALTH_KUBECTL:-k3s kubectl}"
CLUSTER_ISSUER="${HEALTH_CLUSTER_ISSUER:-dawo-appliance-ca}"

CA_CERT="${HEALTH_CA_CERT:-${DAWO_APPLIANCE_CA_CERT:-/var/lib/dawo-appliance/ca/ca.crt}}"
FIREFOX_POLICY="${HEALTH_FIREFOX_POLICY:-/etc/firefox/policies/policies.json}"
CURL_TIMEOUT="${HEALTH_CURL_TIMEOUT:-10}"

# Certificate stability, as upstream: the count must be unchanged for this
# many consecutive comparisons while all are Ready (2 => three equal polls).
CERT_STABLE_POLLS="${HEALTH_CERT_STABLE_POLLS:-2}"
# --once re-polls the certificates this many seconds apart to reach stability.
CERT_SETTLE="${HEALTH_CERT_SETTLE:-5}"

# Injectable commands (tests point these at fakes).
SSH_BIN="${HEALTH_SSH:-ssh}"
CURL_BIN="${HEALTH_CURL:-curl}"
RESOLVE_BIN="${HEALTH_RESOLVE:-resolvectl}"
GETENT_BIN="${HEALTH_GETENT:-getent}"
PING_BIN="${HEALTH_PING:-ping}"

MODE="once"
TIMEOUT="${HEALTH_TIMEOUT:-1800}"
INTERVAL="${HEALTH_POLL_INTERVAL:-15}"
JSON=0

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --once) MODE="once" ;;
    --wait) MODE="wait" ;;
    --timeout) shift; [ $# -gt 0 ] || { echo "--timeout needs a value" >&2; exit 2; }; TIMEOUT="$1" ;;
    --timeout=*) TIMEOUT="${1#*=}" ;;
    --interval) shift; [ $# -gt 0 ] || { echo "--interval needs a value" >&2; exit 2; }; INTERVAL="$1" ;;
    --interval=*) INTERVAL="${1#*=}" ;;
    --json) JSON=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done
case "${TIMEOUT}" in '' | *[!0-9]*) echo "--timeout must be a whole number of seconds" >&2; exit 2 ;; esac
case "${CERT_STABLE_POLLS}" in '' | *[!0-9]*) echo "HEALTH_CERT_STABLE_POLLS must be a whole number" >&2; exit 2 ;; esac

# ---------------------------------------------------------------------------
# Result bookkeeping
# ---------------------------------------------------------------------------
CHECKS=(dns guest node clusterissuer certificates cert_issuers https_dashboard https_oidc browser_trust)
declare -A STATUS=()
declare -A REASON=()

record() { STATUS["$1"]="$2"; REASON["$1"]="$3"; }

all_ok() {
  local c
  for c in "${CHECKS[@]}"; do
    [ "${STATUS[$c]:-}" = "OK" ] || return 1
  done
  return 0
}

count_ok() {
  local c n=0
  for c in "${CHECKS[@]}"; do
    [ "${STATUS[$c]:-}" = "OK" ] && n=$((n + 1))
  done
  echo "${n}"
}

# Number of non-empty lines in a string (avoids `wc -l` padding differences).
nlines() { printf '%s\n' "$1" | awk 'NF { n++ } END { print n + 0 }'; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dawo-health.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

# ---------------------------------------------------------------------------
# Helpers around the injectable commands
# ---------------------------------------------------------------------------
ssh_run() {
  # ssh_run COMMAND...  — runs a command in the guest; the remote command is the
  # LAST argument (fakes rely on that). BatchMode: never prompt from a login hook.
  "${SSH_BIN}" -i "${SSH_KEY}" \
    -o BatchMode=yes -o ConnectTimeout="${SSH_TIMEOUT}" \
    -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR \
    "${VM_USER}@${VM_IP}" "$*"
}

HTTP_CODE=""
HTTP_BODY=""
HTTP_ERR=""
http_get() {
  # http_get URL — HTTPS GET through the appliance CA. Sets HTTP_CODE (3 digits,
  # "000" when no response), HTTP_BODY (file) and HTTP_ERR (curl's message).
  # Returns curl's exit code.
  local url="$1" rc=0
  HTTP_BODY="${TMP}/body"
  : >"${HTTP_BODY}"
  HTTP_CODE="$("${CURL_BIN}" --silent --show-error --cacert "${CA_CERT}" \
    --max-time "${CURL_TIMEOUT}" --output "${HTTP_BODY}" \
    --write-out '%{http_code}' "${url}" 2>"${TMP}/curl.err")" || rc=$?
  HTTP_ERR="$(tr -d '\r' <"${TMP}/curl.err" | head -n 1)"
  [ -n "${HTTP_CODE}" ] || HTTP_CODE="000"
  return "${rc}"
}

http_reason() {
  # http_reason CURL_RC — classify a failed curl call into WAIT/FAIL + reason.
  case "$1" in
    60 | 77 | 91) echo "FAIL certificate not trusted by ${CA_CERT}: ${HTTP_ERR:-curl exit $1}" ;;
    6) echo "WAIT name does not resolve yet" ;;
    7) echo "WAIT connection refused (ingress not listening yet)" ;;
    28) echo "WAIT timed out after ${CURL_TIMEOUT}s" ;;
    35 | 56) echo "WAIT TLS/connection error: ${HTTP_ERR:-curl exit $1}" ;;
    *) echo "WAIT curl exit $1: ${HTTP_ERR:-no details}" ;;
  esac
}

extract_issuer() {
  # extract_issuer FILE — the "issuer" of an OIDC discovery document.
  # jq if present, else python3, else a conservative sed fallback.
  local f="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.issuer // empty' <"${f}" 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("issuer", ""))
except Exception:
    pass' <"${f}" 2>/dev/null || true
  else
    sed -n 's/.*"issuer"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${f}" | head -n 1
  fi
}

# ---------------------------------------------------------------------------
# Checks — each records exactly one result and always returns 0.
# ---------------------------------------------------------------------------
check_dns() {
  local out="" addr=""
  if out="$("${RESOLVE_BIN}" query "${DASHBOARD_HOST}" 2>/dev/null)"; then
    # "bureaublad.dawo.internal: 192.168.150.10   -- link: virbr0"
    addr="$(printf '%s\n' "${out}" | awk -v h="${DASHBOARD_HOST}:" '$1 == h { print $2; exit }')"
  fi
  if [ -z "${addr}" ]; then
    if out="$("${GETENT_BIN}" hosts "${DASHBOARD_HOST}" 2>/dev/null)"; then
      addr="$(printf '%s\n' "${out}" | awk 'NF { print $1; exit }')"
    fi
  fi
  if [ -z "${addr}" ]; then
    record dns WAIT "${DASHBOARD_HOST} does not resolve (resolvectl and getent); expected ${VM_IP}"
  elif [ "${addr}" = "${VM_IP}" ]; then
    record dns OK "${DASHBOARD_HOST} -> ${addr}"
  else
    record dns FAIL "${DASHBOARD_HOST} -> ${addr}, expected the VM at ${VM_IP}"
  fi
}

check_guest() {
  if ssh_run true >/dev/null 2>&1; then
    record guest OK "ssh ${VM_USER}@${VM_IP} accepts the appliance key"
    return 0
  fi
  if [ ! -r "${SSH_KEY}" ]; then
    record guest FAIL "ssh key ${SSH_KEY} is not readable by $(id -un 2>/dev/null || echo '?')"
  elif "${PING_BIN}" -c 1 -W 2 "${VM_IP}" >/dev/null 2>&1; then
    record guest WAIT "${VM_IP} answers ping but ssh does not accept ${VM_USER} yet"
  else
    record guest WAIT "${VM_IP} does not answer ping or ssh (VM booting?)"
  fi
}

check_node() {
  local out total ready
  if ! out="$(ssh_run "${KUBECTL} get node --no-headers" 2>/dev/null)"; then
    record node WAIT "cannot run '${KUBECTL} get node' in the guest"
    return 0
  fi
  total="$(nlines "${out}")"
  ready="$(printf '%s\n' "${out}" | awk 'NF && $2 ~ /^Ready/ { n++ } END { print n + 0 }')"
  if [ "${total}" -eq 0 ]; then
    record node WAIT "no K3s node registered yet"
  elif [ "${total}" -eq "${ready}" ]; then
    record node OK "${ready}/${total} node(s) Ready ($(printf '%s\n' "${out}" | awk 'NR==1 { print $1 }'))"
  else
    record node WAIT "${ready}/${total} node(s) Ready"
  fi
}

check_clusterissuer() {
  local out ready
  if ! out="$(ssh_run "${KUBECTL} get clusterissuer ${CLUSTER_ISSUER} --no-headers" 2>/dev/null)" \
    || [ "$(nlines "${out}")" -eq 0 ]; then
    record clusterissuer WAIT "ClusterIssuer ${CLUSTER_ISSUER} not found (cert-manager not bootstrapped yet)"
    return 0
  fi
  ready="$(printf '%s\n' "${out}" | awk 'NR==1 { print $2 }')"
  if [ "${ready}" = "True" ]; then
    record clusterissuer OK "ClusterIssuer ${CLUSTER_ISSUER} Ready"
  else
    record clusterissuer WAIT "ClusterIssuer ${CLUSTER_ISSUER} READY=${ready:-?}"
  fi
}

# Certificate stability state, kept across --wait iterations (upstream keeps
# it across loop iterations of wait_for_certs).
CERT_PREV=-1
CERT_STABLE=0
CERT_TOTAL=0
CERT_READY=0

cert_observe() {
  # One poll of `kubectl get certificate -A`. Returns 0 when all Ready and the
  # count has been stable for CERT_STABLE_POLLS comparisons, 1 when not yet,
  # 2 when the guest could not be asked.
  local out
  if ! out="$(ssh_run "${KUBECTL} get certificate -A --no-headers" 2>/dev/null)"; then
    CERT_PREV=-1; CERT_STABLE=0; CERT_TOTAL=0; CERT_READY=0
    return 2
  fi
  CERT_TOTAL="$(nlines "${out}")"
  # Columns: NAMESPACE NAME READY SECRET AGE — READY is $3 (as upstream's awk).
  CERT_READY="$(printf '%s\n' "${out}" | awk 'NF && $3 == "True" { n++ } END { print n + 0 }')"
  if [ "${CERT_TOTAL}" -gt 0 ] && [ "${CERT_TOTAL}" -eq "${CERT_READY}" ]; then
    if [ "${CERT_TOTAL}" -eq "${CERT_PREV}" ]; then
      CERT_STABLE=$((CERT_STABLE + 1))
    else
      CERT_STABLE=0
    fi
  else
    CERT_STABLE=0
  fi
  CERT_PREV="${CERT_TOTAL}"
  [ "${CERT_STABLE}" -ge "${CERT_STABLE_POLLS}" ]
}

check_certificates() {
  local rc
  while :; do
    rc=0
    cert_observe || rc=$?
    case "${rc}" in
      0)
        record certificates OK "${CERT_READY}/${CERT_TOTAL} Certificates Ready, count stable over $((CERT_STABLE_POLLS + 1)) polls"
        return 0
        ;;
      2)
        record certificates WAIT "cannot list Certificates in the guest"
        return 0
        ;;
    esac
    if [ "${CERT_TOTAL}" -eq 0 ]; then
      record certificates WAIT "no Certificate resources yet (ingresses not created)"
      return 0
    fi
    if [ "${CERT_TOTAL}" -ne "${CERT_READY}" ]; then
      record certificates WAIT "${CERT_READY}/${CERT_TOTAL} Certificates Ready"
      return 0
    fi
    # All Ready but the count is not stable yet.
    if [ "${MODE}" = "wait" ]; then
      # The next --wait iteration is the next poll (interval = INTERVAL).
      record certificates WAIT "${CERT_READY}/${CERT_TOTAL} Certificates Ready; waiting for the count to settle (${CERT_STABLE}/${CERT_STABLE_POLLS})"
      return 0
    fi
    sleep "${CERT_SETTLE}"
  done
}

check_cert_issuers() {
  local out total bad
  if ! out="$(ssh_run "${KUBECTL} get certificate -A --no-headers -o custom-columns=KIND:.spec.issuerRef.kind,NAME:.spec.issuerRef.name" 2>/dev/null)"; then
    record cert_issuers WAIT "cannot list Certificate issuers in the guest"
    return 0
  fi
  total="$(nlines "${out}")"
  bad="$(printf '%s\n' "${out}" | awk -v n="${CLUSTER_ISSUER}" 'NF && !($1 == "ClusterIssuer" && $2 == n) { b++ } END { print b + 0 }')"
  if [ "${total}" -eq 0 ]; then
    record cert_issuers WAIT "no Certificate resources yet"
  elif [ "${bad}" -gt 0 ]; then
    record cert_issuers FAIL "${bad}/${total} Certificates not issued by ClusterIssuer/${CLUSTER_ISSUER} (tls.selfSigned or wrong annotation?)"
  else
    record cert_issuers OK "${total}/${total} Certificates issued by ClusterIssuer/${CLUSTER_ISSUER}"
  fi
}

check_https_dashboard() {
  local rc=0 r
  if [ ! -r "${CA_CERT}" ]; then
    record https_dashboard FAIL "CA certificate ${CA_CERT} not readable"
    return 0
  fi
  http_get "${DASHBOARD_URL}" || rc=$?
  if [ "${rc}" -ne 0 ]; then
    r="$(http_reason "${rc}")"
    record https_dashboard "${r%% *}" "${DASHBOARD_URL}: ${r#* }"
  elif [ "${HTTP_CODE}" = "200" ]; then
    record https_dashboard OK "${DASHBOARD_URL} -> HTTP 200 (CA ${CA_CERT})"
  else
    record https_dashboard WAIT "${DASHBOARD_URL} -> HTTP ${HTTP_CODE}"
  fi
}

check_https_oidc() {
  local rc=0 r issuer
  if [ ! -r "${CA_CERT}" ]; then
    record https_oidc FAIL "CA certificate ${CA_CERT} not readable"
    return 0
  fi
  http_get "${OIDC_URL}" || rc=$?
  if [ "${rc}" -ne 0 ]; then
    r="$(http_reason "${rc}")"
    record https_oidc "${r%% *}" "${OIDC_URL}: ${r#* }"
    return 0
  fi
  if [ "${HTTP_CODE}" != "200" ]; then
    record https_oidc WAIT "${OIDC_URL} -> HTTP ${HTTP_CODE}"
    return 0
  fi
  issuer="$(extract_issuer "${HTTP_BODY}")"
  if [ -z "${issuer}" ]; then
    record https_oidc WAIT "${OIDC_URL} -> HTTP 200 but no 'issuer' in the body (Keycloak starting?)"
  elif [ "${issuer}" = "${EXPECTED_ISSUER}" ]; then
    record https_oidc OK "${OIDC_URL} -> HTTP 200, issuer ${issuer}"
  else
    record https_oidc FAIL "OIDC issuer is '${issuer}', expected '${EXPECTED_ISSUER}' (global.domain / authentication.oidc mismatch)"
  fi
}

check_browser_trust() {
  if [ ! -r "${CA_CERT}" ]; then
    record browser_trust FAIL "CA certificate ${CA_CERT} not readable (dawo-appliance-ca.service not run?)"
  elif [ ! -r "${FIREFOX_POLICY}" ]; then
    record browser_trust FAIL "Firefox policy file ${FIREFOX_POLICY} missing"
  elif grep -qF -- "${CA_CERT}" "${FIREFOX_POLICY}"; then
    record browser_trust OK "Firefox policy ${FIREFOX_POLICY} installs ${CA_CERT}"
  else
    record browser_trust FAIL "Firefox policy ${FIREFOX_POLICY} does not mention ${CA_CERT}"
  fi
}

run_all() {
  local c
  for c in "${CHECKS[@]}"; do
    "check_${c}"
  done
}

# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------
print_report() {
  # print_report — human report on stdout: STATUS check reason
  local c
  for c in "${CHECKS[@]}"; do
    printf '%-4s %-16s %s\n' "${STATUS[$c]:-WAIT}" "${c}" "${REASON[$c]:-not checked}"
  done
}

json_escape() {
  printf '%s' "$1" | tr -d '\n\r\t' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

print_json() {
  local c healthy="false" sep=""
  all_ok && healthy="true"
  printf '{\n  "healthy": %s,\n  "mode": "%s",\n  "elapsed_seconds": %s,\n' "${healthy}" "${MODE}" "${SECONDS}"
  printf '  "dashboard_url": "%s",\n  "checks": {\n' "$(json_escape "${DASHBOARD_URL}")"
  for c in "${CHECKS[@]}"; do
    local st="${STATUS[$c]:-WAIT}" ok="false"
    [ "${st}" = "OK" ] && ok="true"
    printf '%s    "%s": {"status": "%s", "ok": %s, "reason": "%s"}' \
      "${sep}" "${c}" "${st}" "${ok}" "$(json_escape "${REASON[$c]:-not checked}")"
    sep=",
"
  done
  printf '\n  }\n}\n'
}

final_report() {
  if [ "${JSON}" -eq 1 ]; then
    print_report >&2
    print_json
  else
    print_report
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ "${MODE}" = "once" ]; then
  run_all
  final_report
  all_ok && exit 0
  exit 1
fi

# --wait: poll until all OK or the deadline passes. Progress on stderr.
deadline=$((SECONDS + TIMEOUT))
iteration=0
while :; do
  iteration=$((iteration + 1))
  run_all
  if all_ok; then
    printf '[%4ds] all %d checks OK after %d poll(s)\n' "${SECONDS}" "${#CHECKS[@]}" "${iteration}" >&2
    final_report
    exit 0
  fi
  pending=""
  for c in "${CHECKS[@]}"; do
    [ "${STATUS[$c]:-}" = "OK" ] && continue
    pending="${pending}${pending:+, }${c} (${STATUS[$c]:-WAIT}: ${REASON[$c]:-?})"
  done
  printf '[%4ds] %d/%d OK; %s\n' "${SECONDS}" "$(count_ok)" "${#CHECKS[@]}" "${pending}" >&2
  if [ "${SECONDS}" -ge "${deadline}" ]; then
    printf '[%4ds] timeout after %ds\n' "${SECONDS}" "${TIMEOUT}" >&2
    final_report
    exit 1
  fi
  sleep "${INTERVAL}"
done
