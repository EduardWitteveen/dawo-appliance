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
  && ! grep -q '| user:$' <<<"${out}" \
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

# =============================================================================
# 6. digest pinning (OQ-5, issue #9): phase_values overlays container.<key>.tag
#    with tag@sha256:digest from manifest/image-digests.json; the post-deploy
#    check plans a kubectl imageID comparison; hocuspocus stays unpinned.
# =============================================================================
echo "  -- 6. digest pinning: phase_values overlay vs manifest/image-digests.json --"
DIGESTS="${REPO_ROOT}/manifest/image-digests.json"
[[ -f "${DIGESTS}" ]] || { echo "digest file not found: ${DIGESTS}"; exit 2; }

rc=0
out="$(run_clean env "${common_env[@]}" MB_DOMAIN='dawo.internal' bash "${DEPLOY}" --dry-run --phase values 2>&1)" || rc=$?
if [[ "${rc}" -eq 0 ]] \
  && grep -q "container:" <<<"${out}" \
  && grep -qF 'tag: "26.3.3-debian-12-r0@sha256:da3df0976a9f9a664bdbde6cb5308b78f03ac94d0abf33b2df355bbb06cbc5b9"' <<<"${out}" \
  && grep -qF 'tag: "v5.4.1@sha256:5c299a7ac029ed07fe6d8ae3535201c80728b68a05550536b7e7dd73df13ea40"' <<<"${out}" \
  && grep -qF 'tag: "v16.6.3@sha256:1fa19bef0124d9f8c0839c2d2025c7e073e9e1dfd6b3a87b2839efe4a9179ee2"' <<<"${out}"; then
  ok "phase_values --dry-run emits digest-pinned tags for container.keycloak, container.docs.backend, container.openproject.openproject"
else
  bad "phase_values --dry-run missing expected digest-pinned tag lines (rc=${rc})"; dump "${out}"
fi

if ! grep -q "hocuspocus:" <<<"${out}"; then
  ok "phase_values --dry-run never sets container.openproject.hocuspocus (unresolvable upstream, disabled by upstream's own values)"
else
  bad "phase_values --dry-run unexpectedly declares an openproject.hocuspocus key (manifest/image-digests.json records it as unresolvable/null)"
  dump "${out}"
fi

echo "  -- cross-check: every resolved image in manifest/image-digests.json has a matching --print-pins image_digest_<key> --"
pins_out="$(run_clean bash "${DEPLOY}" --print-pins)"
expected_pins="$("${PY}" - "${DIGESTS}" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
expected = {}
for image, entry in doc["images"].items():
    digest = entry.get("digest")
    if digest is None:
        continue  # unresolvable (hocuspocus): deploy.sh must not pin it
    tag = image.rsplit(":", 1)[-1]
    for key in (k.strip() for k in entry.get("used_by", "").split(",")):
        if key:
            expected[key] = "%s@%s" % (tag, digest)
for key in sorted(expected):
    print("%s\t%s" % (key, expected[key]))
PY
)"
# Native Windows Python opens stdout in text mode and translates \n -> \r\n;
# strip it so the byte-for-byte comparison below is not fooled by a trailing \r.
expected_pins="$(tr -d '\r' <<<"${expected_pins}")"
all_ok=1
report=""
n_checked=0
while IFS=$'\t' read -r key want; do
  [[ -n "${key}" ]] || continue
  n_checked=$((n_checked + 1))
  got="$(grep -F "image_digest_${key}=" <<<"${pins_out}" | head -n1)"
  got="${got#image_digest_"${key}"=}"
  if [[ "${got}" != "${want}" ]]; then
    all_ok=0
    report="${report}image_digest_${key}: want '${want}', got '${got:-<absent>}'"$'\n'
  fi
done <<<"${expected_pins}"
if [[ "${all_ok}" -eq 1 && "${n_checked}" -gt 0 ]]; then
  ok "all ${n_checked} resolved manifest/image-digests.json entries have a matching, exact image_digest_<key> in --print-pins"
else
  bad "digest pins in --print-pins do not match manifest/image-digests.json (checked ${n_checked}):"
  dump "${report}"
fi

if ! grep -q "image_digest_openproject.hocuspocus=" <<<"${pins_out}"; then
  ok "--print-pins has no image_digest_openproject.hocuspocus (unresolvable upstream; would be wrong to pin a digest that does not exist)"
else
  bad "--print-pins unexpectedly pins openproject.hocuspocus"
fi

echo "  -- post-deploy digest verification is planned by phase_wait_certs --"
rc=0
out="$(run_clean env "${common_env[@]}" MB_DOMAIN='dawo.internal' bash "${DEPLOY}" --dry-run --phase wait-certs 2>&1)" || rc=$?
if [[ "${rc}" -eq 0 ]] \
  && grep -qF "kubectl get pods -A -o json" <<<"${out}" \
  && grep -q "pinned digests" <<<"${out}"; then
  ok "phase_wait_certs --dry-run plans the post-deploy image-digest verification (kubectl get pods -A -o json, warn-only)"
else
  bad "phase_wait_certs --dry-run missing the digest-verification plan line (rc=${rc})"; dump "${out}"
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

# =============================================================================
# 7. MB_PROFILE=laptop-demo (#110): micro preset, core apps only, no 05/06
# =============================================================================
echo "  -- 7. profile laptop-demo --"
state_lap="${tmp}/state-laptop"
reset_logs
rc=0
out="$(run_clean env "${common_env[@]}" MB_DOMAIN='dawo.internal' MB_PROFILE=laptop-demo \
  MB_STATE_DIR="${state_lap}" MB_MASTER_PASSWORD_FILE="${state_lap}/master-password" \
  MB_SRC_DIR="${state_lap}/mijn-bureau-infra" MB_DOWNLOAD_DIR="${state_lap}/downloads" \
  FAKE_HELM_VERSION="${p_helm_ver}" FAKE_HELMFILE_VERSION="${p_helmfile_ver}" \
  FAKE_HELM_DIFF_VERSION="${p_helmdiff_ver#v}" \
  bash "${DEPLOY}" --dry-run 2>&1)" || rc=$?
if [[ "${rc}" -eq 0 ]] \
  && grep -q '|   resourcesPreset: "micro"' <<<"${out}" \
  && grep -A1 '| backup:$' <<<"${out}" | grep -q '|   enabled: false' \
  && grep -q '|   drive:         { enabled: false }' <<<"${out}" \
  && grep -q '|   conversations: { enabled: false }' <<<"${out}" \
  && grep -A3 '| resource:$' <<<"${out}" | grep -q '|     limits: { cpu: "2", memory: "2Gi" }' \
  && grep -q 'rollout status deploy/collabora-online --timeout=900s' <<<"${out}" \
  && grep -q 'patch deploy/collabora-online --type strategic: container collabora args \["--o:ssl.enable=false","--o:ssl.termination=true",.*"--o:storage.wopi.alias_groups.group\[0\].host=https://nextcloud.dawo.internal"' <<<"${out}" \
  && [[ "$(grep -n 'container collabora args' <<<"${out}" | cut -d: -f1)" -lt "$(grep -n 'rollout status deploy/collabora-online' <<<"${out}" | cut -d: -f1)" ]] \
  && ! grep -q 'resourcesPresetPerApp' <<<"${out}" \
  && grep -q 'kubectl -n mb-bureaublad patch deploy/bureaublad-backend --type strategic: .*env SSL_CERT_FILE,REQUESTS_CA_BUNDLE=' <<<"${out}" \
  && grep -A6 '^.*| user:$' <<<"${out}" | grep -q '|     username: dawo' \
  && grep -A6 '^.*| user:$' <<<"${out}" | grep -q '|     password: dawo' \
  && [[ "$(grep -c '|     username: ' <<<"${out}")" -eq 1 ]] \
  && grep -q '|   grist:       { enabled: false' <<<"${out}" \
  && grep -q '|   docs:        { enabled: false' <<<"${out}" \
  && grep -q '|   nextcloud:   { enabled: true' <<<"${out}" \
  && grep -q '05-docs.sh skipped' <<<"${out}" && grep -q '06-grist.sh skipped' <<<"${out}" \
  && grep -q 'kubectl create namespace mb-grist' <<<"${out}" \
  && ! grep -q 'DRY-RUN: bash .*03-restart-oidc-apps.sh' <<<"${out}" \
  && [[ ! -e "${state_lap}" ]]; then
  ok "laptop-demo dry-run: micro preset, no per-app override, grist/docs/meet/livekit off, drive/conversations off (#134), backup off (#127), Collabora 2 CPU/2 GiB, args patched before the phase-13 wait (#150, #154), one demo user dawo/dawo (#159), Bureaublad backend trusts the CA (#163), 05/06 skipped, own 03 steps, namespaces ensured"
else
  bad "laptop-demo dry-run (rc=${rc})"; dump "${out}"
fi
rc=0
out="$(run_clean env "${common_env[@]}" MB_PROFILE=bogus bash "${DEPLOY}" --dry-run --phase values 2>&1)" || rc=$?
if [[ "${rc}" -ne 0 ]] && grep -q 'MB_PROFILE must be full or laptop-demo' <<<"${out}"; then
  ok "an unknown MB_PROFILE is refused before any phase runs"
else
  bad "unknown MB_PROFILE was not refused (rc=${rc})"; dump "${out}"
fi

# wait_rollout (#124): a stale ProgressDeadlineExceeded (after a clock jump or
# an interrupted run) must not fail a deployment that is Available; a
# deployment that is really not ready must still fail. The function is taken
# out of deploy.sh and run against a fake kubectl, without --dry-run.
wr_bin="${tmp}/wrbin"; mkdir -p "${wr_bin}"
cat >"${wr_bin}/kubectl" <<'EOF2'
#!/usr/bin/env bash
case "$*" in
  *"rollout status"*) [[ "${FAKE_ROLLOUT:-ok}" == ok ]] && exit 0; echo 'error: deployment "x" exceeded its progress deadline' >&2; exit 1 ;;
  *'type=="Available"'*) echo "${FAKE_AVAILABLE:-True}" ;;
  *"spec.replicas"*) echo 1 ;;
  *"readyReplicas"*) echo "${FAKE_READY:-1}" ;;
esac
EOF2
chmod +x "${wr_bin}/kubectl"
wr_fn="$(sed -n '/^wait_rollout() {/,/^}/p' "${DEPLOY}")"
wr() { env PATH="${wr_bin}:${PATH}" "$@" bash -c 'DRY_RUN=0; warn() { echo "WARNING: $*"; }; '"${wr_fn}"'; wait_rollout cert-manager cert-manager 5s' 2>&1; }
r1=0; wr FAKE_ROLLOUT=ok >/dev/null || r1=$?
r2=0; o2="$(wr FAKE_ROLLOUT=deadline FAKE_AVAILABLE=True FAKE_READY=1)" || r2=$?
r3=0; o3="$(wr FAKE_ROLLOUT=deadline FAKE_AVAILABLE=False FAKE_READY=0)" || r3=$?
if [[ -n "${wr_fn}" && "${r1}" -eq 0 && "${r2}" -eq 0 && "${o2}" == *"Available with 1/1 ready replicas"* && "${r3}" -ne 0 ]]; then
  ok "wait_rollout: a normal rollout passes; a stale progress deadline on an Available deployment passes with a warning; a deployment that is not Available fails (#124)"
else
  bad "wait_rollout (r1=${r1} r2=${r2} r3=${r3})"; dump "${o2}"; dump "${o3}"
fi

# verify_image_digests (#140): the pinned list must reach python3 (not only
# kubectl), and a failing check must only warn. Run without --dry-run against
# a fake kubectl that prints one pod at a pinned digest and one that is not.
py=""
for c in python3 python; do
  # A real interpreter (the fakes above also answer to python3 and exit 0).
  if command -v "${c}" >/dev/null 2>&1 && [[ "$("${c}" -c 'import json; print(6*7)' 2>/dev/null | tr -d '\r')" == 42 ]]; then py="$(command -v "${c}")"; break; fi
done
if [[ -z "${py}" ]]; then
  echo "  SKIP verify_image_digests: no working python3/python here"
else
  vd_bin="${tmp}/vdbin"; mkdir -p "${vd_bin}"
  printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "${py}" >"${vd_bin}/python3"
  cat >"${vd_bin}/kubectl" <<'EOF2'
#!/usr/bin/env bash
[[ "${FAKE_KUBECTL_FAIL:-0}" == 1 ]] && exit 1
cat <<'JSON'
{"items":[
 {"metadata":{"namespace":"mb-keycloak","name":"kc-0"},"status":{"containerStatuses":[{"name":"kc","image":"x/kc:1","imageID":"docker.io/x/kc@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}},
 {"metadata":{"namespace":"kube-system","name":"coredns-1"},"status":{"containerStatuses":[{"name":"coredns","image":"coredns:1","imageID":"docker.io/coredns@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}}
]}
JSON
EOF2
  chmod +x "${vd_bin}"/*
  vd_fn="$(sed -n '/^verify_image_digests() {/,/^}/p' "${DEPLOY}")"
  vd() { env PATH="${vd_bin}:${PATH}" "$@" bash -c 'set -euo pipefail; DRY_RUN=0; log() { echo "==> $*"; }; warn() { echo "WARNING: $*"; }
    MB_KNOWN_DIGESTS=(sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)
    '"${vd_fn}"'; verify_image_digests; echo "RC_AFTER=0"' 2>&1; }
  v1=0; ov1="$(vd FAKE_KUBECTL_FAIL=0)" || v1=$?
  v2=0; ov2="$(vd FAKE_KUBECTL_FAIL=1)" || v2=$?
  if [[ -n "${vd_fn}" && "${v1}" -eq 0 && "${ov1}" == *"at a pinned digest: 1; not matching any pinned digest: 1"* \
        && "${ov1}" == *"kube-system/coredns-1"* && "${ov1}" == *"RC_AFTER=0"* \
        && "${v2}" -eq 0 && "${ov2}" == *"RC_AFTER=0"* ]]; then
    ok "verify_image_digests: the pinned list reaches python3 (1 pinned, 1 not); an empty kubectl answer does not fail the phase (#140)"
  else
    bad "verify_image_digests (v1=${v1} v2=${v2})"; dump "${ov1}"; dump "${ov2}"
  fi
fi

# phase_sessions (#156): the Keycloak admin password must reach curl on stdin
# byte for byte. A here-string added a newline, which --data-urlencode "@-"
# encoded as %0A (401 on the Dell). Run without --dry-run against a fake
# kubectl and a fake curl that records its stdin and argv.
if [[ -z "${py}" ]]; then
  echo "  SKIP phase_sessions: no working python3/python here"
else
  ps_bin="${tmp}/psbin"; ps_rec="${tmp}/psrec"; mkdir -p "${ps_bin}" "${ps_rec}"
  printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "${py}" >"${ps_bin}/python3"
  cat >"${ps_bin}/kubectl" <<'EOF2'
#!/usr/bin/env bash
case "$*" in
  *"get node"*) echo "192.168.150.10" ;;
  *"secret keycloak-keycloak"*) printf '%s' 's3cr3t' | base64 ;;
esac
EOF2
  cat >"${ps_bin}/curl" <<'EOF2'
#!/usr/bin/env bash
n=0; while [[ -e "${PS_REC}/argv.${n}" ]]; do n=$((n + 1)); done
printf '%s\n' "$@" >"${PS_REC}/argv.${n}"
cat >"${PS_REC}/stdin.${n}"
[[ "$*" == *openid-connect/token* ]] && echo '{"access_token":"tok123"}'
exit 0
EOF2
  chmod +x "${ps_bin}"/*
  ps_fn="$(sed -n '/^realm_settings_json() {/,/^}/p; /^phase_sessions() {/,/^}/p' "${DEPLOY}")"
  po=""; prc=0
  po="$(env PATH="${ps_bin}:${PATH}" PS_REC="${ps_rec}" bash -c 'set -euo pipefail; DRY_RUN=0; MB_DOMAIN=dawo.internal; CA_CRT=/nonexistent/ca.crt; AUTOLOGIN_THEME=dawo-autologin
    log() { echo "==> $*"; }; info() { echo "    $*"; }; die() { echo "ERROR: $*"; exit 1; }; require_ca_files() { :; }
    '"${ps_fn}"'; phase_sessions' 2>&1)" || prc=$?
  if [[ -n "${ps_fn}" && "${prc}" -eq 0 && -s "${ps_rec}/stdin.0" ]] && cmp -s "${ps_rec}/stdin.0" <(printf '%s' 's3cr3t') \
      && ! grep -q 's3cr3t' "${ps_rec}/argv.0" "${ps_rec}/argv.1" \
      && grep -q 'Authorization: Bearer tok123' "${ps_rec}/stdin.1" && ! grep -q 'tok123' "${ps_rec}/argv.1"; then
    ok "phase_sessions: the Keycloak password reaches curl on stdin without a trailing newline; password and token stay out of argv (#156)"
  else
    bad "phase_sessions (rc=${prc})"; dump "${po}"; od -c "${ps_rec}/stdin.0" 2>/dev/null | head -3
  fi
fi

# Auto-login for the laptop profile (#173): phase 13 mounts a Keycloak login
# theme (ConfigMap into the StatefulSet), phase 14 selects it on the realm;
# the full profile does neither. The theme script is run against a stub DOM
# when node is available.
echo "  -- 8. auto-login theme (laptop profile) --"
al_state="${tmp}/state-autologin"
reset_logs
rc=0
out="$(run_clean env "${common_env[@]}" MB_DOMAIN='dawo.internal' MB_PROFILE=laptop-demo \
  MB_STATE_DIR="${al_state}" MB_MASTER_PASSWORD_FILE="${al_state}/master-password" \
  MB_SRC_DIR="${al_state}/mijn-bureau-infra" MB_DOWNLOAD_DIR="${al_state}/downloads" \
  FAKE_HELM_VERSION="${p_helm_ver}" FAKE_HELMFILE_VERSION="${p_helmfile_ver}" \
  FAKE_HELM_DIFF_VERSION="${p_helmdiff_ver#v}" \
  bash "${DEPLOY}" --dry-run 2>&1)" || rc=$?
cm_line="$(grep -n 'apply ConfigMap dawo-autologin-theme' <<<"${out}" | head -1 | cut -d: -f1)"
w4_line="$(grep -n 'DRY-RUN: bash .*04-nextcloud-office.sh' <<<"${out}" | head -1 | cut -d: -f1)"
if [[ "${rc}" -eq 0 && -n "${cm_line}" && -n "${w4_line}" && "${cm_line}" -gt "${w4_line}" ]] \
  && grep -q 'patch statefulset/keycloak-keycloak --type strategic: mount ConfigMap dawo-autologin-theme at /opt/bitnami/keycloak/themes/dawo-autologin' <<<"${out}" \
  && grep -q 'rollout status statefulset/keycloak-keycloak --timeout=600s' <<<"${out}" \
  && grep -q 'admin/realms/mijnbureau {.*"rememberMe":true,"loginTheme":"dawo-autologin"}' <<<"${out}"; then
  ok "laptop-demo: phase 13 mounts the auto-login theme after upstream 04 and waits for Keycloak; phase 14 sets loginTheme dawo-autologin"
else
  bad "laptop-demo auto-login dry-run (rc=${rc})"; dump "${out}"
fi
reset_logs
rc=0
out="$(run_clean env "${common_env[@]}" MB_DOMAIN='dawo.internal' MB_PROFILE=full \
  MB_STATE_DIR="${al_state}" MB_MASTER_PASSWORD_FILE="${al_state}/master-password" \
  MB_SRC_DIR="${al_state}/mijn-bureau-infra" MB_DOWNLOAD_DIR="${al_state}/downloads" \
  FAKE_HELM_VERSION="${p_helm_ver}" FAKE_HELMFILE_VERSION="${p_helmfile_ver}" \
  FAKE_HELM_DIFF_VERSION="${p_helmdiff_ver#v}" \
  bash "${DEPLOY}" --dry-run 2>&1)" || rc=$?
if [[ "${rc}" -eq 0 ]] && ! grep -q 'dawo-autologin' <<<"${out}" && ! grep -q 'loginTheme' <<<"${out}" \
  && grep -q 'admin/realms/mijnbureau {.*"rememberMe":true}' <<<"${out}"; then
  ok "full profile: no auto-login theme, no loginTheme"
else
  bad "full profile auto-login check (rc=${rc})"; dump "${out}"
fi

# patch_keycloak_autologin without --dry-run, against a fake kubectl that
# records its argv and stdin.
al_bin="${tmp}/albin"; al_rec="${tmp}/alrec"; mkdir -p "${al_bin}" "${al_rec}"
cat >"${al_bin}/kubectl" <<'EOF2'
#!/usr/bin/env bash
# Unique names: `create configmap | apply -f -` runs two of these at once.
printf '%s\n' "$@" >"$(mktemp "${AL_REC}/argv.XXXXXX")"
case "$*" in
  *"create configmap"*) printf 'apiVersion: v1\nkind: ConfigMap\n' ;;
  *"apply -f -"*) cat >"$(mktemp "${AL_REC}/stdin.XXXXXX")" ;;
esac
exit 0
EOF2
# The PATH above has a no-op sha256sum; this one hashes (via the Python 3
# resolved at the top, before the fakes).
printf '#!/usr/bin/env bash\nexec "%s" -c "import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest() + \\"  -\\")"\n' "${PY}" >"${al_bin}/sha256sum"
chmod +x "${al_bin}/kubectl" "${al_bin}/sha256sum"
al_fn="$(sed -n '/^autologin_theme_properties() {/,/^}$/p; /^autologin_theme_js() {/,/^}$/p; /^patch_keycloak_autologin() {/,/^}$/p' "${DEPLOY}")"
ao=""; arc=0
ao="$(env PATH="${al_bin}:${PATH}" AL_REC="${al_rec}" bash -c 'set -euo pipefail; DRY_RUN=0
  AUTOLOGIN_THEME=dawo-autologin; AUTOLOGIN_CONFIGMAP=dawo-autologin-theme; KEYCLOAK_STS=keycloak-keycloak
  info() { echo "    $*"; }; warn() { echo "WARNING: $*"; }; die() { echo "ERROR: $*"; exit 1; }
  '"${al_fn}"'; patch_keycloak_autologin' 2>&1)" || arc=$?
al_all="$(cat "${al_rec}"/argv.* 2>/dev/null || true)"
if [[ -n "${al_fn}" && "${arc}" -eq 0 ]] \
  && grep -q '^--from-file=theme.properties=' <<<"${al_all}" && grep -q '^--from-file=dawo-autologin.js=' <<<"${al_all}" \
  && grep -q '"path":"login/theme.properties"' <<<"${al_all}" \
  && grep -q '"path":"login/resources/js/dawo-autologin.js"' <<<"${al_all}" \
  && grep -q '"mountPath":"/opt/bitnami/keycloak/themes/dawo-autologin","readOnly":true' <<<"${al_all}" \
  && grep -Eq '"dawo-appliance/autologin-sha256":"[0-9a-f]{64}"' <<<"${al_all}" \
  && grep -q '^statefulset/keycloak-keycloak$' <<<"${al_all}" \
  && grep -q 'kind: ConfigMap' "${al_rec}"/stdin.* 2>/dev/null; then
  ok "patch_keycloak_autologin: ConfigMap with theme.properties and the script, mounted read-only into Keycloak's themes, hash annotation, rollout wait"
else
  bad "patch_keycloak_autologin (rc=${arc})"; dump "${ao}"; dump "${al_all}"
fi

# The theme itself: child of Keycloak's stock theme, one script.
th="$(bash -c "$(sed -n '/^autologin_theme_properties() {/,/^}$/p' "${DEPLOY}"); autologin_theme_properties")"
if grep -qx 'parent=keycloak' <<<"${th}" && grep -qx 'scripts=js/dawo-autologin.js' <<<"${th}"; then
  ok "theme.properties: parent=keycloak, scripts=js/dawo-autologin.js"
else
  bad "theme.properties"; dump "${th}"
fi

# The script against a stub DOM: signs in once; not again in the same tab;
# not when the page shows an error; nothing on pages without the login form.
if command -v node >/dev/null 2>&1; then
  js="${tmp}/dawo-autologin.js"
  bash -c "$(sed -n '/^autologin_theme_js() {/,/^}$/p' "${DEPLOY}"); autologin_theme_js" >"${js}"
  cat >"${tmp}/stubdom.js" <<'EOF2'
const fs = require("fs");
const vm = require("vm");
const src = fs.readFileSync(process.argv[2], "utf8");
function page({ form = true, error = false, store }) {
  const el = {};
  let clicks = 0;
  if (form) {
    el["kc-form-login"] = {};
    el["username"] = { value: "" };
    el["password"] = { value: "" };
    el["rememberMe"] = { checked: false };
    el["kc-login"] = { click() { clicks++; } };
  }
  const document = {
    readyState: "complete",
    getElementById: (id) => el[id] || null,
    querySelector: () => (error ? {} : null),
    addEventListener() {},
  };
  const sessionStorage = {
    getItem: (k) => (k in store ? store[k] : null),
    setItem: (k, v) => { store[k] = String(v); },
  };
  vm.runInNewContext(src, { document, window: { sessionStorage } });
  return { clicks, el };
}
const results = [];
const tab = {};
const a = page({ store: tab });
results.push(a.clicks === 1 && a.el.username.value === "dawo" && a.el.password.value === "dawo" && a.el.rememberMe.checked === true);
results.push(page({ store: tab }).clicks === 0);
results.push(page({ error: true, store: {} }).clicks === 0);
results.push(page({ form: false, store: {} }).clicks === 0);
console.log(results.join(" "));
process.exit(results.every(Boolean) ? 0 : 1);
EOF2
  jo=""; jrc=0
  jo="$(node "${tmp}/stubdom.js" "${js}" 2>&1)" || jrc=$?
  if [[ "${jrc}" -eq 0 ]]; then
    ok "auto-login script: fills dawo/dawo and submits once; not again in the same tab; not after an error; nothing without the login form"
  else
    bad "auto-login script against a stub DOM (${jo})"
  fi
else
  echo "  SKIP auto-login script behaviour: node not installed here"
fi

echo
echo "test-mijnbureau-driver: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
