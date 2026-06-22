#!/usr/bin/env bash
#
# Local test for the appliance bootstrap dry-run.
# Requires no Nix, no root, and no network. Safe to run anywhere.
#
# Asserts:
#   1. The manifest checksum file matches the committed manifest.
#   2. `plan` against the trusted manifest verifies and prints a plan (exit 0),
#      and reports that no disk writes were performed.
#   3. A tampered manifest is rejected (non-zero exit, no plan).
#   4. Passing --target-disk / --confirm-destroy is refused (non-zero exit),
#      i.e. the destructive path is not reachable in v0.1.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="${REPO_ROOT}/installer/bootstrap/dawo-appliance-bootstrap"
MANIFEST="${REPO_ROOT}/manifest/appliance-manifest.json"
SHA_FILE="${REPO_ROOT}/manifest/appliance-manifest.json.sha256"

pass=0
fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }

run_bootstrap() { bash "${BOOTSTRAP}" "$@"; }

echo "test-bootstrap-dryrun: starting"
[[ -f "${BOOTSTRAP}" ]] || { echo "bootstrap not found: ${BOOTSTRAP}"; exit 2; }
[[ -f "${MANIFEST}" ]]  || { echo "manifest not found: ${MANIFEST}"; exit 2; }
[[ -f "${SHA_FILE}" ]]  || { echo "sha file not found: ${SHA_FILE}"; exit 2; }

# --- 1. manifest and its committed checksum are in sync --------------------
expected="$(awk 'NR==1{print $1}' "${SHA_FILE}")"
actual="$(sha256sum "${MANIFEST}" | awk '{print $1}')"
if [[ "${expected}" == "${actual}" ]]; then
  ok "committed manifest matches its .sha256 (${actual:0:12}…)"
else
  bad "manifest and .sha256 out of sync (run: make manifest-sum)"
fi

# --- 2. plan against the trusted manifest succeeds -------------------------
out=""
if out="$(run_bootstrap plan --offline \
            --manifest-url "file://${MANIFEST}" 2>&1)"; then
  if grep -q "INSTALL PLAN" <<<"${out}" \
     && grep -q "NO DISK WRITES PERFORMED" <<<"${out}" \
     && grep -q "checksum verified" <<<"${out}"; then
    ok "plan verifies checksum, prints plan, reports no disk writes"
  else
    bad "plan ran but output missing expected markers"
    printf '%s\n' "${out}" | sed 's/^/      | /'
  fi
else
  bad "plan exited non-zero against a valid manifest"
  printf '%s\n' "${out}" | sed 's/^/      | /'
fi

# --- 3. tampered manifest is rejected --------------------------------------
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dawo-test.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT
tampered="${tmp}/appliance-manifest.json"
# Change the content so the checksum no longer matches the trusted .sha256.
sed 's/"version": "0.1.0-dev"/"version": "9.9.9-evil"/' "${MANIFEST}" >"${tampered}"

if run_bootstrap plan --offline \
      --manifest-url "file://${tampered}" \
      --expected-sha256-file "${SHA_FILE}" >/dev/null 2>&1; then
  bad "tampered manifest was ACCEPTED (should have been rejected)"
else
  ok "tampered manifest rejected (checksum mismatch)"
fi

# --- 4. destructive flags are refused --------------------------------------
if run_bootstrap plan --offline \
      --manifest-url "file://${MANIFEST}" \
      --target-disk /dev/null --confirm-destroy >/dev/null 2>&1; then
  bad "destructive flags were accepted (should be refused in v0.1)"
else
  ok "destructive flags refused (no write path in v0.1)"
fi

echo "test-bootstrap-dryrun: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
