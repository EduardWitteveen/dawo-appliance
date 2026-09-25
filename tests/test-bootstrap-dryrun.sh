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
#   4. Passing --target-disk / --confirm-destroy to `plan` is refused.
#   5-8. `install` gating: needs a target, refuses non-devices, --dry-run
#      previews and writes nothing, no --confirm-destroy -> refused.
#   9. The password stage tree (`--generate-password`) has the layout and modes
#      disko-install can copy without changing the mode of `/` (needs mkpasswd;
#      skipped where it is not installed).

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

# --- 4. plan/verify refuse destructive flags -------------------------------
if run_bootstrap plan --offline \
      --manifest-url "file://${MANIFEST}" \
      --target-disk /dev/null --confirm-destroy >/dev/null 2>&1; then
  bad "plan accepted destructive flags (should be refused)"
else
  ok "plan refuses --target-disk / --confirm-destroy"
fi

# --- 5. install requires an explicit target disk ---------------------------
if run_bootstrap install >/dev/null 2>&1; then
  bad "install ran without --target-disk (should refuse)"
else
  ok "install refuses without --target-disk"
fi

# --- 6. install refuses a non-block-device target --------------------------
# A real install must hit the block-device check before any write. /dev/null is
# a character device, never a valid install target.
if run_bootstrap install --target-disk /dev/null --confirm-destroy >/dev/null 2>&1; then
  bad "install accepted a non-block-device target (should refuse)"
else
  ok "install refuses a non-block-device target"
fi

# --- 7. install --dry-run previews and writes nothing ----------------------
out=""
if out="$(run_bootstrap install --target-disk /dev/dawo-nonexistent --dry-run 2>&1)"; then
  if grep -q "INSTALL PLAN" <<<"${out}" \
     && grep -q "NO DISK WRITES PERFORMED" <<<"${out}" \
     && grep -q "disko-install --flake" <<<"${out}"; then
    ok "install --dry-run previews the plan and writes nothing"
  else
    bad "install --dry-run output missing expected markers"
    printf '%s\n' "${out}" | sed 's/^/      | /'
  fi
else
  bad "install --dry-run exited non-zero"
  printf '%s\n' "${out}" | sed 's/^/      | /'
fi

# --- 7b. install --dry-run --generate-password previews the password step ---
out=""
if out="$(run_bootstrap install --target-disk /dev/dawo-nonexistent --dry-run --generate-password 2>&1)"; then
  if grep -q "extra-files" <<<"${out}" && grep -q "NO DISK WRITES PERFORMED" <<<"${out}"; then
    ok "install --dry-run --generate-password previews the password hash step"
  else
    bad "install --dry-run --generate-password output missing expected markers"
    printf '%s\n' "${out}" | sed 's/^/      | /'
  fi
else
  bad "install --dry-run --generate-password exited non-zero"
fi

# --- 8. install without confirmation (and not dry-run) refuses -------------
# Even if the device check were to pass, the missing --confirm-destroy must stop
# it. We use a non-block device so nothing can be written regardless.
if run_bootstrap install --target-disk /dev/dawo-nonexistent >/dev/null 2>&1; then
  bad "install ran without --confirm-destroy (should refuse)"
else
  ok "install refuses without --confirm-destroy"
fi

# --- 9. password stage tree: modes safe for `cp -ar STAGE/var ROOT/var` ------
# Needs the whois `mkpasswd` (yescrypt, --stdin); Git Bash ships a Cygwin tool of
# the same name that cannot do this, hence the capability probe.
if printf 'x
' | mkpasswd -m yescrypt --stdin >/dev/null 2>&1; then
  stage="${tmp}/stage"; root="${tmp}/root"
  mkdir -p "${stage}" "${root}"; chmod 700 "${stage}"; chmod 755 "${root}"
  if STAGE_DIR="${stage}" STAGE_PASSWORD="test-pw" run_bootstrap stage-password-files >/dev/null 2>&1 \
     && cp -ar "${stage}/var" "${root}/var" \
     && [[ "$(stat -c %a "${root}")" == "755" ]] \
     && [[ "$(stat -c %a "${root}/var")" == "755" ]] \
     && [[ "$(stat -c %a "${root}/var/lib/dawo-appliance")" == "755" ]] \
     && [[ "$(stat -c %a "${root}/var/lib/dawo-appliance/dawo.password-hash")" == "600" ]] \
     && [[ "$(stat -c %a "${root}/var/lib/dawo-appliance/dawo.password.txt")" == "644" ]] \
     && grep -qx "test-pw" "${root}/var/lib/dawo-appliance/dawo.password.txt" \
     && grep -q '^[$]y[$]' "${root}/var/lib/dawo-appliance/dawo.password-hash"; then
    ok "password stage tree copies with safe modes (root stays 755, hash 600, text 644)"
  else
    bad "password stage tree has wrong layout or modes"
    find "${root}" -printf '%M %p
' 2>/dev/null | sed 's/^/      | /'
  fi
else
  echo "  SKIP password stage tree (mkpasswd not installed here; covered by nix flake check)"
fi

# --- 10. default manifest URL follows the shipped version (docs/releasing.md) --
dev_default="$(run_bootstrap help 2>&1 | sed -n 's/.*Default: //p' | head -1)"
if [[ "${dev_default}" == "file://${REPO_ROOT}/manifest/appliance-manifest.json" ]]; then
  ok "dev build defaults to the shipped manifest (file://)"
else
  bad "dev default manifest URL is '${dev_default}'"
fi
rel="${tmp}/rel"; mkdir -p "${rel}/installer/bootstrap" "${rel}/manifest"
cp "${BOOTSTRAP}" "${rel}/installer/bootstrap/"
sed 's/"version": "[^"]*-dev"/"version": "9.8.7"/' "${MANIFEST}" > "${rel}/manifest/appliance-manifest.json"
( cd "${rel}/manifest" && sha256sum appliance-manifest.json > appliance-manifest.json.sha256 )
rel_default="$(bash "${rel}/installer/bootstrap/dawo-appliance-bootstrap" help 2>&1 | sed -n 's/.*Default: //p' | head -1)"
if [[ "${rel_default}" == "https://github.com/EduardWitteveen/dawo-appliance/releases/download/v9.8.7/appliance-manifest.json" ]]; then
  ok "release build defaults to the asset of exactly its own tag"
else
  bad "release default manifest URL is '${rel_default}'"
fi

echo "test-bootstrap-dryrun: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
