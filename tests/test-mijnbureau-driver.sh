#!/usr/bin/env bash
#
# Offline test for apps/mijn-bureau/deploy.sh (Slice 6).
# Requires no Nix, no root, no network and no real cluster: every external
# command deploy.sh shells out to (kubectl, curl, git, tar, install,
# sha256sum, python3, openssl) is a logging no-op fake prepended onto PATH,
# and helm/helmfile are faked through the driver's own MB_BIN_DIR override
# (the least invasive interception point, since deploy.sh already reads every
# other path from an environment variable). Runs on Linux, WSL and Windows Git
# Bash (bash 4+, awk, sed, and Python 3 for the manifest cross-check —
# `python3`, or `python` as Windows Git Bash ships it).
#
# Asserts:
#   1. `--dry-run` (all 14 phases) exits 0, prints a "[n/14]" line for every
#      phase in order, ends with "NOTHING WAS CHANGED", creates no state
#      directory, and never actually invokes kubectl/curl/git/tar/install/
#      sha256sum/python3 (the one command that legitimately always runs even
#      in dry-run, the CA basicConstraints check via openssl, runs exactly
#      once through the fake).
#   2. MB_DOMAIN validation runs before every phase, not just phase_preflight
#      (the gap closed by the run_phase() fix): a malformed MB_DOMAIN is
#      rejected, looped over every phase from --list-phases, with zero
#      phase-specific output; and concretely for --phase password, the
#      password file is never written when the domain is rejected.
#   3. phase_password generates a 32-char alnum password once and reuses it
#      unchanged on a second run (idempotent; second run says "reusing").
#   4. MB_REV, HELMFILE_VERSION and CERT_MANAGER_VERSION (from --print-pins)
#      equal manifest/appliance-manifest.json's mijn_bureau.rev and
#      mijn_bureau.tooling.{helmfile,cert_manager}. HELM_VERSION and
#      HELM_DIFF_VERSION, and every *_SHA256 constant, are not recorded a
#      second time anywhere in this repository, so those are checked for
#      well-formedness only (documented as such, not claimed as cross-checked).
#   5. phase_tools only downloads a tool whose installed_version does not
#      match the pin; phase_issuer's dry-run output contains the exact
#      ClusterIssuer/CA-secret commands ADR 0004 describes; --list-phases
#      lists all 14 phases; an unknown --phase is refused; shellcheck passes
#      (skipped when not installed).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY="${REPO_ROOT}/apps/mijn-bureau/deploy.sh"
MANIFEST="${REPO_ROOT}/manifest/appliance-manifest.json"

pass=0
fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
dump() { printf '%s\n' "$1" | sed 's/^/      | /'; }

echo "test-mijnbureau-driver: starting"
[[ -f "${DEPLOY}" ]]   || { echo "driver not found: ${DEPLOY}"; exit 2; }
[[ -f "${MANIFEST}" ]] || { echo "manifest not found: ${MANIFEST}"; exit 2; }

# Windows Git Bash usually ships `python` (3.x) without a `python3` alias.
# Resolved BEFORE the PATH override below installs a fake `python3`.
PY="$(command -v python3 || command -v python || true)"
if [[ -z "${PY}" ]] || ! "${PY}" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)'; then
  echo "python 3 is required for the manifest cross-check (looked for python3, python)"; exit 2
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/dawo-mb-test.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

fakebin="${tmp}/fakebin"   # kubectl, curl, git, tar, install, sha256sum, python3, openssl
mbbin="${tmp}/mbbin"       # MB_BIN_DIR: fake helm, helmfile
ca_dir="${tmp}/ca"         # dummy CA material (require_ca_files just checks non-empty files)
logs="${tmp}/logs"
mkdir -p "${fakebin}" "${mbbin}" "${ca_dir}" "${logs}"

printf -- '-----BEGIN CERTIFICATE-----\nMIIBfakeDAWOapplianceCA\n-----END CERTIFICATE-----\n' >"${ca_dir}/ca.crt"
printf -- '-----BEGIN EC PRIVATE KEY-----\nfake\n-----END EC PRIVATE KEY-----\n' >"${ca_dir}/ca.key"

# --- fakes: catch-all logger for tools this driver must never actually run
# under --dry-run (kubectl, curl, git, tar, install, sha256sum, python3). If
# any of these fire, it lands in unexpected.log instead of touching anything
# real, and the tests below assert that file never appears.
cat >"${fakebin}/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"${FAKE_LOG_DIR:?}/unexpected.log"
exit 0
EOF
for t in curl git tar install sha256sum python3; do
  cp "${fakebin}/kubectl" "${fakebin}/${t}"
done

# openssl: the CA basicConstraints sanity check in phase_preflight runs even
# in --dry-run (it is a read-only local check, not gated). Logs the call and
# answers CA:TRUE unless FAKE_OPENSSL_NO_CA=1.
cat >"${fakebin}/openssl" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'openssl %s\n' "$*" >>"${FAKE_LOG_DIR:?}/openssl.log"
case "$*" in
  *"-ext basicConstraints"*)
    echo "X509v3 Basic Constraints: critical"
    [[ "${FAKE_OPENSSL_NO_CA:-0}" == "1" ]] || echo "CA:TRUE"
    ;;
esac
exit 0
EOF

chmod +x "${fakebin}"/*

# helm/helmfile: deploy.sh already reads these through MB_BIN_DIR, so faking
# them needs no PATH trick. installed_version() runs "$@" unconditionally
# (not gated by --dry-run), so these fire on every phase_tools run.
cat >"${mbbin}/helm" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'helm %s\n' "$*" >>"${FAKE_LOG_DIR:?}/helm.log"
case "$*" in
  "version --template "*)
    printf '%s' "${FAKE_HELM_VERSION:-}" ;;
  "plugin list")
    printf 'NAME\tVERSION\tDESCRIPTION\n'
    [[ -n "${FAKE_HELM_DIFF_VERSION:-}" ]] && printf 'diff\t%s\tShows a diff between releases\n' "${FAKE_HELM_DIFF_VERSION}"
    ;;
  "env HELM_PLUGINS")
    printf '%s\n' "${FAKE_HELM_PLUGINS_DIR:-${TMPDIR:-/tmp}/fake-helm-plugins}" ;;
esac
exit 0
EOF

cat >"${mbbin}/helmfile" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'helmfile %s\n' "$*" >>"${FAKE_LOG_DIR:?}/helmfile.log"
case "$*" in
  "--version")
    printf 'helmfile version v%s\n' "${FAKE_HELMFILE_VERSION:-0.0.0}" ;;
esac
exit 0
EOF

chmod +x "${mbbin}"/*

export FAKE_LOG_DIR="${logs}"
export PATH="${fakebin}:${PATH}"

reset_logs() { rm -f "${logs}"/*.log 2>/dev/null || true; }

# Common environment every invocation gets: fake tool dir + fixture CA + a
# kubeconfig path that must never actually be read in any scenario below.
common_env=(MB_BIN_DIR="${mbbin}" APPLIANCE_CA_DIR="${ca_dir}" KUBECONFIG="${tmp}/no-such-kubeconfig")

# Run with every MB_*/FAKE_* variable cleared first, so nothing leaks in from
# the caller's shell (mirrors tests/test-k3s-install.sh's run_clean).
run_clean() {
  env -u MB_DOMAIN -u APPLIANCE_CA_DIR -u MB_STATE_DIR -u MB_MASTER_PASSWORD_FILE \
    -u MB_SRC_DIR -u MB_DOWNLOAD_DIR -u MB_BIN_DIR -u MB_CERT_TIMEOUT -u KUBECONFIG \
    -u FAKE_HELM_VERSION -u FAKE_HELMFILE_VERSION -u FAKE_HELM_DIFF_VERSION -u FAKE_OPENSSL_NO_CA \
    "$@"
}

# --- pins, read once via --print-pins --------------------------------------
pins_raw="$(run_clean bash "${DEPLOY}" --print-pins)"
get_pin() { printf '%s\n' "${pins_raw}" | sed -n "s/^$1=//p"; }
p_rev="$(get_pin mijn_bureau_rev)"
p_helmfile_ver="$(get_pin helmfile_version)"
p_helmfile_sha="$(get_pin helmfile_sha256)"
p_helm_ver="$(get_pin helm_version)"
p_helm_url="$(get_pin helm_url)"
p_helm_sha="$(get_pin helm_sha256)"
p_helmdiff_ver="$(get_pin helm_diff_version)"
p_helmdiff_sha="$(get_pin helm_diff_sha256)"
p_cm_ver="$(get_pin cert_manager_version)"
p_cm_sha="$(get_pin cert_manager_sha256)"

# =============================================================================
# 1. full --dry-run: prints a plan, touches no real files/state
# =============================================================================
echo "  -- 1. full --dry-run touches nothing --"
state_fresh="${tmp}/state-fullrun"
reset_logs
rc=0
out="$(run_clean env "${common_env[@]}" MB_DOMAIN='dawo.internal' MB_STATE_DIR="${state_fresh}" \
  MB_MASTER_PASSWORD_FILE="${state_fresh}/master-password" \
  MB_SRC_DIR="${state_fresh}/mijn-bureau-infra" MB_DOWNLOAD_DIR="${state_fresh}/downloads" \
  FAKE_HELM_VERSION="${p_helm_ver}" FAKE_HELMFILE_VERSION="${p_helmfile_ver}" \
  FAKE_HELM_DIFF_VERSION="${p_helmdiff_ver#v}" \
  bash "${DEPLOY}" --dry-run 2>&1)" || rc=$?

all_phase_lines=1
for n in $(seq 1 14); do
  grep -qE "\[${n}/14\]" <<<"${out}" || all_phase_lines=0
done

if [[ "${rc}" -eq 0 ]] \
  && [[ "${all_phase_lines}" -eq 1 ]] \
  && grep -q "DRY-RUN complete. NOTHING WAS CHANGED." <<<"${out}" \
  && ! grep -q "WARNING:" <<<"${out}" \
  && [[ ! -e "${state_fresh}" ]] \
  && [[ ! -e "${logs}/unexpected.log" ]]; then
  ok "--dry-run exits 0, plans all 14 phases in order, creates no state directory, calls no real kubectl/curl/git/tar/install/sha256sum/python3"
else
  bad "full --dry-run did not behave as expected (rc=${rc})"
  dump "${out}"
  [[ -e "${logs}/unexpected.log" ]] && dump "unexpected real invocations: $(cat "${logs}/unexpected.log")"
fi

if [[ -s "${logs}/openssl.log" ]] && [[ "$(wc -l <"${logs}/openssl.log")" -eq 1 ]] \
  && grep -qF "x509 -in ${ca_dir}/ca.crt -noout -ext basicConstraints" "${logs}/openssl.log"; then
  ok "the CA basicConstraints sanity check runs exactly once, against the CA fixture, even under --dry-run"
else
  bad "unexpected openssl invocations"; dump "$(cat "${logs}/openssl.log" 2>/dev/null || echo '(no log)')"
fi

# =============================================================================
# 2. MB_DOMAIN validation runs before every phase (run_phase fix)
# =============================================================================
echo "  -- 2. a malformed MB_DOMAIN is rejected before any phase runs --"
mapfile -t phase_names < <(run_clean bash "${DEPLOY}" --list-phases | awk '{print $2}')
if [[ "${#phase_names[@]}" -eq 14 ]]; then
  ok "--list-phases lists all 14 phases (used to drive the domain-validation sweep below)"
else
  bad "--list-phases printed ${#phase_names[@]} phase names, expected 14"
fi

bad_domain_phases=()
for name in "${phase_names[@]}"; do
  rc=0
  out="$(run_clean env "${common_env[@]}" MB_DOMAIN='bad_domain.internal' \
    bash "${DEPLOY}" --dry-run --phase "${name}" 2>&1)" || rc=$?
  if [[ "${rc}" -eq 0 ]] \
    || ! grep -q "MB_DOMAIN is not a valid DNS name: bad_domain.internal" <<<"${out}" \
    || grep -qE '\[[0-9]+/14\]' <<<"${out}"; then
    bad_domain_phases+=("${name}")
  fi
done
if [[ "${#bad_domain_phases[@]}" -eq 0 ]]; then
  ok "run_phase() rejects a malformed MB_DOMAIN before dispatch, for all 14 phases (not just phase_preflight)"
else
  bad "malformed MB_DOMAIN was NOT rejected before phase dispatch for: ${bad_domain_phases[*]}"
fi

# Concrete, non-dry-run proof for one phase: the rejected domain must leave no
# trace, i.e. phase_password's body never ran.
badpw_state="${tmp}/state-badpw"
rc=0
out="$(run_clean env "${common_env[@]}" MB_DOMAIN='bad_domain.internal' MB_STATE_DIR="${badpw_state}" \
  MB_MASTER_PASSWORD_FILE="${badpw_state}/master-password" \
  bash "${DEPLOY}" --phase password 2>&1)" || rc=$?
if [[ "${rc}" -ne 0 ]] && grep -q "MB_DOMAIN is not a valid DNS name" <<<"${out}" \
  && [[ ! -e "${badpw_state}/master-password" ]]; then
  ok "--phase password with a bad MB_DOMAIN exits non-zero and never writes the password file (the exact gap the run_phase fix closed)"
else
  bad "bad MB_DOMAIN did not block --phase password as expected (rc=${rc})"
  dump "${out}"
fi

# =============================================================================
# 3. phase_password: generate once, reuse thereafter
# =============================================================================
echo "  -- 3. phase_password is idempotent --"
pw_state="${tmp}/state-password"
pw_file="${pw_state}/master-password"
rc=0
out1="$(run_clean env "${common_env[@]}" MB_DOMAIN='dawo.internal' MB_STATE_DIR="${pw_state}" \
  MB_MASTER_PASSWORD_FILE="${pw_file}" bash "${DEPLOY}" --phase password 2>&1)" || rc=$?
if [[ "${rc}" -eq 0 ]] && [[ -s "${pw_file}" ]] && grep -q "generated new master password" <<<"${out1}"; then
  ok "phase_password generates a password file on first run"
else
  bad "phase_password first run failed (rc=${rc})"; dump "${out1}"
fi

pw1="$(cat "${pw_file}" 2>/dev/null || true)"
if [[ "${pw1}" =~ ^[A-Za-z0-9]{32}$ ]]; then
  ok "generated password is exactly 32 alphanumeric characters"
else
  bad "generated password has unexpected shape: '${pw1}' (${#pw1} chars)"
fi

rc=0
out2="$(run_clean env "${common_env[@]}" MB_DOMAIN='dawo.internal' MB_STATE_DIR="${pw_state}" \
  MB_MASTER_PASSWORD_FILE="${pw_file}" bash "${DEPLOY}" --phase password 2>&1)" || rc=$?
pw2="$(cat "${pw_file}" 2>/dev/null || true)"
if [[ "${rc}" -eq 0 ]] && grep -q "reusing existing master password" <<<"${out2}" \
  && [[ -n "${pw1}" ]] && [[ "${pw2}" == "${pw1}" ]]; then
  ok "a second run reuses the existing password unchanged (idempotent, does not regenerate)"
else
  bad "second run regenerated or altered the master password (rc=${rc})"
  dump "${out2}"
fi

# =============================================================================
# 4. pins equal manifest/appliance-manifest.json where the manifest tracks them
# =============================================================================
echo "  -- 4. pins vs manifest/appliance-manifest.json --"
manifest_vals="$("${PY}" -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
mb = d["mijn_bureau"]
print(mb["rev"])
print(mb["tooling"]["helmfile"])
print(mb["tooling"]["cert_manager"])
' "${MANIFEST}" | tr -d '\r')"
mapfile -t mv <<<"${manifest_vals}"
m_rev="${mv[0]}"; m_helmfile="${mv[1]}"; m_cm="${mv[2]}"

if [[ -n "${p_rev}" && "${p_rev}" == "${m_rev}" ]]; then
  ok "MB_REV (${p_rev:0:12}...) equals manifest mijn_bureau.rev"
else
  bad "MB_REV '${p_rev}' != manifest mijn_bureau.rev '${m_rev}'"
fi
if [[ -n "${p_helmfile_ver}" && "${p_helmfile_ver}" == "${m_helmfile}" ]]; then
  ok "HELMFILE_VERSION (${p_helmfile_ver}) equals manifest mijn_bureau.tooling.helmfile"
else
  bad "HELMFILE_VERSION '${p_helmfile_ver}' != manifest tooling.helmfile '${m_helmfile}'"
fi
if [[ -n "${p_cm_ver}" && "${p_cm_ver}" == "${m_cm}" ]]; then
  ok "CERT_MANAGER_VERSION (${p_cm_ver}) equals manifest mijn_bureau.tooling.cert_manager"
else
  bad "CERT_MANAGER_VERSION '${p_cm_ver}' != manifest tooling.cert_manager '${m_cm}'"
fi

# HELM_VERSION, HELM_DIFF_VERSION and every *_SHA256 constant have no second
# recorded copy anywhere in this repository (grepped for at write time), so
# there is nothing to cross-check them against. Format-only, said plainly.
sha_ok=1
for pair in "HELMFILE_SHA256:${p_helmfile_sha}" "HELM_SHA256:${p_helm_sha}" \
            "HELM_DIFF_SHA256:${p_helmdiff_sha}" "CERT_MANAGER_SHA256:${p_cm_sha}"; do
  cname="${pair%%:*}"; cval="${pair#*:}"
  [[ "${cval}" =~ ^[0-9a-f]{64}$ ]] || { sha_ok=0; dump "${cname}='${cval}' is not a 64-char lowercase hex sha256"; }
done
if [[ "${sha_ok}" -eq 1 ]]; then
  ok "HELMFILE_SHA256, HELM_SHA256, HELM_DIFF_SHA256 and CERT_MANAGER_SHA256 are well-formed sha256 digests (no second source recorded in this repo to cross-check them against)"
else
  bad "one or more *_SHA256 constants are not well-formed sha256 digests"
fi

if [[ "${p_helm_ver}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "${p_helmdiff_ver}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  ok "HELM_VERSION (${p_helm_ver}) and HELM_DIFF_VERSION (${p_helmdiff_ver}) are well-formed (manifest does not track these two independently; nothing to cross-check them against)"
else
  bad "HELM_VERSION/HELM_DIFF_VERSION do not look like vX.Y.Z: '${p_helm_ver}' / '${p_helmdiff_ver}'"
fi

# =============================================================================
# 5. other cheaply-testable behaviour
# =============================================================================
echo "  -- 5. phase_tools only downloads what does not match the pin --"
reset_logs
rc=0
out_a="$(run_clean env "${common_env[@]}" MB_DOMAIN='dawo.internal' \
  FAKE_HELM_VERSION="${p_helm_ver}" FAKE_HELMFILE_VERSION="${p_helmfile_ver}" \
  FAKE_HELM_DIFF_VERSION="${p_helmdiff_ver#v}" \
  bash "${DEPLOY}" --dry-run --phase tools 2>&1)" || rc=$?
if [[ "${rc}" -eq 0 ]] \
  && grep -qF "helm ${p_helm_ver} already installed" <<<"${out_a}" \
  && grep -qF "helmfile ${p_helmfile_ver} already installed" <<<"${out_a}" \
  && grep -qF "helm-diff ${p_helmdiff_ver} already installed" <<<"${out_a}" \
  && [[ "$(grep -c "DRY-RUN: curl -fsSL" <<<"${out_a}")" -eq 0 ]]; then
  ok "phase_tools: helm, helmfile and helm-diff all already at the pinned version -> zero downloads"
else
  bad "phase_tools (all pinned) unexpected output (rc=${rc})"; dump "${out_a}"
fi

reset_logs
rc=0
out_b="$(run_clean env "${common_env[@]}" MB_DOMAIN='dawo.internal' \
  FAKE_HELM_VERSION="v0.0.0-stale" FAKE_HELMFILE_VERSION="${p_helmfile_ver}" \
  FAKE_HELM_DIFF_VERSION="${p_helmdiff_ver#v}" \
  bash "${DEPLOY}" --dry-run --phase tools 2>&1)" || rc=$?
if [[ "${rc}" -eq 0 ]] \
  && grep -qF "DRY-RUN: curl -fsSL ${p_helm_url} " <<<"${out_b}" \
  && grep -qF "helmfile ${p_helmfile_ver} already installed" <<<"${out_b}" \
  && grep -qF "helm-diff ${p_helmdiff_ver} already installed" <<<"${out_b}" \
  && [[ "$(grep -c "DRY-RUN: curl -fsSL" <<<"${out_b}")" -eq 1 ]]; then
  ok "phase_tools: a stale helm alone triggers exactly one download, of its own release URL"
else
  bad "phase_tools (stale helm) unexpected output (rc=${rc})"; dump "${out_b}"
fi

echo "  -- phase_issuer emits the ADR 0004 ClusterIssuer/CA-secret commands --"
rc=0
out="$(run_clean env "${common_env[@]}" MB_DOMAIN='dawo.internal' bash "${DEPLOY}" --dry-run --phase issuer 2>&1)" || rc=$?
if [[ "${rc}" -eq 0 ]] \
  && grep -qF "kubectl -n cert-manager create secret tls dawo-appliance-ca --cert=${ca_dir}/ca.crt --key=${ca_dir}/ca.key" <<<"${out}" \
  && grep -q "kind: ClusterIssuer" <<<"${out}" \
  && grep -q "name: dawo-appliance-ca" <<<"${out}" \
  && grep -q "secretName: dawo-appliance-ca" <<<"${out}" \
  && grep -qF "DRY-RUN: kubectl wait --for=condition=Ready clusterissuer/dawo-appliance-ca --timeout=120s" <<<"${out}"; then
  ok "phase_issuer --dry-run prints the CA secret command and a ClusterIssuer manifest naming dawo-appliance-ca"
else
  bad "phase_issuer --dry-run output missing expected markers (rc=${rc})"; dump "${out}"
fi

echo "  -- --phase rejects an unknown name; unknown top-level args refused --"
if run_clean bash "${DEPLOY}" --phase bogus >/dev/null 2>&1; then
  bad "--phase bogus was accepted (should be refused)"
else
  ok "--phase bogus is refused"
fi
if run_clean bash "${DEPLOY}" --nonsense >/dev/null 2>&1; then
  bad "unknown top-level argument accepted"
else
  ok "unknown top-level argument refused"
fi

echo "  -- shellcheck --"
SHELLCHECK_BIN="$(command -v shellcheck || true)"
if [[ -z "${SHELLCHECK_BIN}" && -x "${HOME}/.local/shellcheck/shellcheck.exe" ]]; then
  SHELLCHECK_BIN="${HOME}/.local/shellcheck/shellcheck.exe"
fi
if [[ -n "${SHELLCHECK_BIN}" ]]; then
  if "${SHELLCHECK_BIN}" "${DEPLOY}" "${BASH_SOURCE[0]}"; then
    ok "shellcheck clean (deploy.sh, this test)"
  else
    bad "shellcheck reported findings"
  fi
else
  echo "  SKIP shellcheck (not installed here)"
fi

echo
echo "test-mijnbureau-driver: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
