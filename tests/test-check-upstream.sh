#!/usr/bin/env bash
#
# Offline test for scripts/check-upstream.sh's fixtures mode
# (CHECK_UPSTREAM_FIXTURES). Requires no Nix, no root and no network: every
# fetch() call is answered from canned files under a temp directory instead
# of curl. Runs on Linux, WSL and Windows Git Bash (bash 4+, Python 3 via
# `python3` or `python`, no jq).
#
# The pinned values used to build fixtures (DAWO-Core tag, nixpkgs ref,
# cert-manager version) are read from the real manifest/appliance-manifest.json
# and from the script's own --json output (the "dawo-core tag" row's "pinned"
# field, which is always printed even when the row itself errors), so this
# test keeps working as pins are bumped.
#
# Asserts:
#   1. A newer DAWO-Core tag is flagged NEWER AVAILABLE (dawo_tags fixture).
#   2. A stale/idle pinned nixpkgs branch with a newer branch already
#      existing is flagged EOL (nixpkgs_head + nixpkgs_branch_* fixtures).
#   3. cert-manager pinned outside the two newest supported minors is
#      flagged EOL (a second, differently-computed EOL heuristic in the
#      same script).
#   4. The DAWO-Core README "## Notice" section changing is flagged MOVED
#      (dawo_readme fixture; hash-compared against NOTICE_BASELINE).
#   5. A fixture .status file (403, 429) is reported as an UNKNOWN row with
#      the HTTP code in the note; a key with no fixture file at all is
#      reported UNKNOWN with "no fixture <key>".
#   6. --markdown FILE writes the table to disk (heading, fixtures marker,
#      the row in Markdown-table form) and --json produces well-formed JSON
#      with a "fixtures": true flag and a "checked" timestamp.
#   7. -h/--help, an unknown option, a --markdown without a FILE argument,
#      and a nonexistent CHECK_UPSTREAM_FIXTURES directory are all handled
#      as documented (exit codes and messages). There is no --check-style
#      flag in this script (only --json/--markdown/-h), so nothing to test
#      there.
#   8. The GITHUB_TOKEN argv-safety fix (commit c5576bb: the token goes to
#      curl via `-K -` on stdin, never as a literal argv element) is NOT
#      exercised by fixtures mode, since fixtures bypass the curl/subprocess
#      code path entirely. This is checked instead as a static grep
#      assertion against the script's source (see part 8 below).
#   9. shellcheck passes on both scripts (skipped when not installed).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-upstream.sh"
MANIFEST="${REPO_ROOT}/manifest/appliance-manifest.json"

pass=0
fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
dump() { printf '%s\n' "$1" | sed 's/^/      | /'; }

echo "test-check-upstream: starting"
[[ -f "${SCRIPT}" ]]   || { echo "script not found: ${SCRIPT}"; exit 2; }
[[ -f "${MANIFEST}" ]] || { echo "manifest not found: ${MANIFEST}"; exit 2; }

# Windows Git Bash usually ships `python` (3.x) without a `python3` alias.
PY="$(command -v python3 || command -v python || true)"
if [[ -z "${PY}" ]] || ! "${PY}" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)'; then
  echo "python 3 is required for the JSON assertions (looked for python3, python)"; exit 2
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/dawo-check-upstream-test.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

# --- helpers -----------------------------------------------------------------

# run_cu FIXTURES_DIR NOW ARGS... — always clears GITHUB_TOKEN (fixtures mode
# never uses it, but a leaked one must not change behaviour) and sets a fixed
# CHECK_UPSTREAM_NOW when NOW is non-empty, for deterministic EOL/idle math.
run_cu() {
  local fx="$1" now="$2"
  shift 2
  env -u GITHUB_TOKEN CHECK_UPSTREAM_FIXTURES="${fx}" CHECK_UPSTREAM_NOW="${now}" bash "${SCRIPT}" "$@"
}

# get_row_field JSON_TEXT COMPONENT FIELD — pull one field off one row of a
# --json run by exact component name (rows carry component/pinned/latest/
# status/link/note).
get_row_field() {
  printf '%s' "$1" | "${PY}" -c '
import json, sys
d = json.load(sys.stdin)
component, field = sys.argv[1], sys.argv[2]
for r in d["rows"]:
    if r["component"].strip() == component:
        print(r.get(field, ""))
        sys.exit(0)
print("__NOTFOUND__")
' "$2" "$3"
}

# --- pinned values, read from the real manifest + the script's own output ---
# nixpkgs_ref and cert_manager are read straight off the manifest (the script
# does the same, with no fallback). dawo-core's pinned tag has a
# flake.lock-first, manifest-fallback in the script; rather than reimplement
# that here, read it back from a fixtures run with no dawo_tags fixture at
# all — the "pinned" field of an UNKNOWN row is filled in before the fetch is
# even attempted, so it's the authoritative value either way. This doubles as
# the "no fixture for this key" assertion (part 5).
manifest_vals="$("${PY}" -c '
import json, sys
m = json.load(sys.stdin)
print(m["nix"]["nixpkgs"]["ref"])
print(m["mijn_bureau"]["tooling"]["cert_manager"])
' <"${MANIFEST}" | tr -d '\r')"
mapfile -t mv <<<"${manifest_vals}"
nixpkgs_ref="${mv[0]}"
cm="${mv[1]}"

empty_fx="${tmp}/fx-empty"
mkdir -p "${empty_fx}"
out_baseline="$(run_cu "${empty_fx}" "" --json)"
dc_tag="$(get_row_field "${out_baseline}" "dawo-core tag" pinned)"
status_baseline="$(get_row_field "${out_baseline}" "dawo-core tag" status)"
note_baseline="$(get_row_field "${out_baseline}" "dawo-core tag" note)"

if [[ "${status_baseline}" == "UNKNOWN" && "${note_baseline}" == "no fixture dawo_tags"* ]] && [[ -n "${dc_tag}" && "${dc_tag}" != "__NOTFOUND__" ]]; then
  ok "an empty fixtures dir: 'dawo-core tag' is UNKNOWN, note 'no fixture dawo_tags' (pinned='${dc_tag}' still reported)"
else
  bad "empty fixtures dir did not behave as expected"
  dump "status=${status_baseline} note=${note_baseline} dc_tag=${dc_tag}"
fi

# Derived fixture values (newer DAWO-Core tag; two newer cert-manager minors;
# the first branch next_branches() would look for after nixpkgs_ref).
extra="$("${PY}" -c '
import re, sys

def bump_patch(tag):
    parts = tag.split(".")
    parts[-1] = str(int(parts[-1]) + 1)
    return ".".join(parts)

def bump_minor(tag, n):
    v = tag.lstrip("v")
    major, minor, _patch = v.split(".")
    return "v%s.%s.0" % (major, int(minor) + n)

def next_branches(ref):
    m = re.match(r"^nixos-(\d+)\.(\d+)$", ref)
    if not m:
        return []
    y, mo = int(m.group(1)), int(m.group(2))
    out = []
    for _ in range(2):
        y, mo = (y, 11) if mo == 5 else (y + 1, 5)
        out.append("nixos-%02d.%02d" % (y, mo))
    return out

dc_tag, nixpkgs_ref, cm = sys.argv[1], sys.argv[2], sys.argv[3]
nb = next_branches(nixpkgs_ref)
print(bump_patch(dc_tag))
print(bump_minor(cm, 1))
print(bump_minor(cm, 2))
print(nb[0] if nb else "")
' "${dc_tag}" "${nixpkgs_ref}" "${cm}" | tr -d '\r')"
mapfile -t ev <<<"${extra}"
dc_newer="${ev[0]}"
cm_newer1="${ev[1]}"
cm_newer2="${ev[2]}"
nixpkgs_branch1="${ev[3]}"

if [[ -z "${nixpkgs_branch1}" ]]; then
  echo "  SKIP nixpkgs EOL scenario (nixpkgs ref '${nixpkgs_ref}' does not match nixos-YY.MM)"
fi

# =============================================================================
# 1. dawo-core: a newer tag is flagged NEWER AVAILABLE
# =============================================================================
echo "  -- 1. newer DAWO-Core tag --"
fx1="${tmp}/fx-dawo-newer"
mkdir -p "${fx1}"
cat >"${fx1}/dawo_tags.json" <<EOF
[{"name": "${dc_tag}"}, {"name": "${dc_newer}"}]
EOF
out1="$(run_cu "${fx1}" "" --json)"
status1="$(get_row_field "${out1}" "dawo-core tag" status)"
latest1="$(get_row_field "${out1}" "dawo-core tag" latest)"
if [[ "${status1}" == "NEWER AVAILABLE" && "${latest1}" == "${dc_newer}" ]]; then
  ok "dawo-core tag ${dc_tag} -> ${dc_newer}: flagged NEWER AVAILABLE"
else
  bad "dawo-core tag newer-tag scenario failed"
  dump "status=${status1} latest=${latest1} (expected NEWER AVAILABLE / ${dc_newer})"
fi

# =============================================================================
# 2. nixpkgs: idle pinned branch + a newer branch existing is flagged EOL
# =============================================================================
if [[ -n "${nixpkgs_branch1}" ]]; then
  echo "  -- 2. stale nixpkgs branch (EOL) --"
  fx2="${tmp}/fx-nixpkgs-eol"
  mkdir -p "${fx2}"
  cat >"${fx2}/nixpkgs_head.json" <<'EOF'
{"sha": "0000000000000000000000000000000000000a", "commit": {"committer": {"date": "2026-01-01T00:00:00Z"}}}
EOF
  cat >"${fx2}/nixpkgs_branch_${nixpkgs_branch1}.json" <<'EOF'
{}
EOF
  out2="$(run_cu "${fx2}" "2026-06-01" --json)"
  component2="nixpkgs ${nixpkgs_ref}"
  status2="$(get_row_field "${out2}" "${component2}" status)"
  note2="$(get_row_field "${out2}" "${component2}" note)"
  if [[ "${status2}" == "EOL" && "${note2}" == "no commits for 151 days; ${nixpkgs_branch1} exists" ]]; then
    ok "nixpkgs ${nixpkgs_ref} idle 151 days with ${nixpkgs_branch1} existing: flagged EOL"
  else
    bad "nixpkgs EOL scenario failed"
    dump "status=${status2} note=${note2} (expected EOL / 'no commits for 151 days; ${nixpkgs_branch1} exists')"
  fi
fi

# =============================================================================
# 3. cert-manager: pinned outside the two newest supported minors is EOL
#    (a second, differently-computed EOL heuristic in the same script)
# =============================================================================
echo "  -- 3. cert-manager pinned minor unsupported (EOL) --"
fx3="${tmp}/fx-certmanager-eol"
mkdir -p "${fx3}"
cat >"${fx3}/certmanager_releases.json" <<EOF
[
  {"tag_name": "${cm}", "prerelease": false, "draft": false},
  {"tag_name": "${cm_newer1}", "prerelease": false, "draft": false},
  {"tag_name": "${cm_newer2}", "prerelease": false, "draft": false}
]
EOF
out3="$(run_cu "${fx3}" "" --json)"
status3="$(get_row_field "${out3}" "cert-manager (upstream pin)" status)"
note3="$(get_row_field "${out3}" "cert-manager (upstream pin)" note)"
if [[ "${status3}" == "EOL" && "${note3}" == "only the two newest minors are supported (pinned upstream)" ]]; then
  ok "cert-manager ${cm}, with ${cm_newer1} and ${cm_newer2} also released: flagged EOL"
else
  bad "cert-manager EOL scenario failed"
  dump "status=${status3} note=${note3}"
fi

# =============================================================================
# 4. dawo-core notice: README "## Notice" section changing is flagged MOVED
# =============================================================================
echo "  -- 4. DAWO-Core README Notice changed (MOVED) --"
fx4="${tmp}/fx-notice-moved"
mkdir -p "${fx4}"
cat >"${fx4}/dawo_readme.txt" <<'EOF'
# DAWO-Core

## Notice

This project has moved to a different forge.

## Other section

irrelevant
EOF
out4="$(run_cu "${fx4}" "" --json)"
status4="$(get_row_field "${out4}" "dawo-core notice" status)"
note4="$(get_row_field "${out4}" "dawo-core notice" note)"
if [[ "${status4}" == "MOVED" && "${note4}" == "README Notice changed: This project has moved to a different forge."* ]]; then
  ok "dawo-core notice: a changed ## Notice section is flagged MOVED"
else
  bad "dawo-core notice MOVED scenario failed"
  dump "status=${status4} note=${note4}"
fi

# =============================================================================
# 5. fixture .status (403/429) and a key with no fixture at all
# =============================================================================
echo "  -- 5. rate-limit-style fixture errors and missing fixtures --"
fx5="${tmp}/fx-errors"
mkdir -p "${fx5}"
printf '403\n' >"${fx5}/k3s_releases.status"
printf '429\n' >"${fx5}/certmanager_releases.status"
out5="$(run_cu "${fx5}" "" --json)"
status5_k3s="$(get_row_field "${out5}" "k3s" status)"
note5_k3s="$(get_row_field "${out5}" "k3s" note)"
status5_cm="$(get_row_field "${out5}" "cert-manager (upstream pin)" status)"
note5_cm="$(get_row_field "${out5}" "cert-manager (upstream pin)" note)"
status5_dc="$(get_row_field "${out5}" "dawo-core tag" status)"
note5_dc="$(get_row_field "${out5}" "dawo-core tag" note)"
if [[ "${status5_k3s}" == "UNKNOWN" && "${note5_k3s}" == "HTTP 403 (fixture)" ]] \
  && [[ "${status5_cm}" == "UNKNOWN" && "${note5_cm}" == "HTTP 429 (fixture)" ]] \
  && [[ "${status5_dc}" == "UNKNOWN" && "${note5_dc}" == "no fixture dawo_tags" ]]; then
  ok "a 403 and a 429 .status fixture both report UNKNOWN with the HTTP code in the note; a key with no fixture file reports 'no fixture <key>'"
else
  bad "rate-limit / missing-fixture scenario failed"
  dump "k3s: ${status5_k3s} / ${note5_k3s}"
  dump "cert-manager: ${status5_cm} / ${note5_cm}"
  dump "dawo-core tag: ${status5_dc} / ${note5_dc}"
fi

# =============================================================================
# 6. --markdown FILE writes the table; --json is well-formed
# =============================================================================
echo "  -- 6. --markdown writes a file; --json is well-formed --"
md_file="${tmp}/report.md"
rc=0
out6="$(run_cu "${fx1}" "" --markdown "${md_file}")" || rc=$?
if [[ "${rc}" -eq 0 ]] && grep -qE "Wrote .*report\.md" <<<"${out6}" && [[ -s "${md_file}" ]]; then
  ok "--markdown ${md_file##*/} exits 0 and prints 'Wrote <file>' on the table stdout"
else
  bad "--markdown did not report writing the file as expected (rc=${rc})"
  dump "${out6}"
fi
md_content="$(cat "${md_file}" 2>/dev/null || true)"
if grep -qF "# Upstream check" <<<"${md_content}" \
  && grep -qF "(fixtures)." <<<"${md_content}" \
  && grep -qF "| dawo-core tag | \`${dc_tag}\` | \`${dc_newer}\` | **NEWER AVAILABLE**" <<<"${md_content}"; then
  ok "the markdown file has the heading, the fixtures marker, and the dawo-core tag row in table form"
else
  bad "markdown file content missing expected markers"
  dump "${md_content}"
fi

if printf '%s' "${out1}" | "${PY}" -c '
import json, sys
d = json.load(sys.stdin)
assert d["fixtures"] is True, d
assert isinstance(d["rows"], list) and len(d["rows"]) > 0, d
assert isinstance(d["summary"], dict), d
import re
assert re.match(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC$", d["checked"]), d["checked"]
'; then
  ok "--json output: fixtures=true, a non-empty rows list, a summary dict, a well-formed 'checked' timestamp"
else
  bad "--json output did not parse or match the expected shape"
  dump "${out1}"
fi

# =============================================================================
# 7. arg handling: --help, unknown option, --markdown with no FILE, a
#    nonexistent CHECK_UPSTREAM_FIXTURES dir. No --check-style flag exists
#    (only --json / --markdown FILE / -h|--help): usage() is the whole set.
# =============================================================================
echo "  -- 7. argument and fixtures-dir error handling --"
rc=0
out7="$(bash "${SCRIPT}" --help 2>&1)" || rc=$?
if [[ "${rc}" -eq 0 ]] && grep -q "CHECK_UPSTREAM_FIXTURES" <<<"${out7}" && grep -q -- "--markdown FILE" <<<"${out7}"; then
  ok "--help exits 0 and documents CHECK_UPSTREAM_FIXTURES and --markdown FILE"
else
  bad "--help did not behave as expected (rc=${rc})"; dump "${out7}"
fi

set +e
bash "${SCRIPT}" --bogus >/dev/null 2>&1
rc=$?
set -e
if [[ "${rc}" -eq 2 ]]; then
  ok "an unknown option is refused with exit 2"
else
  bad "unknown option did not exit 2 (rc=${rc})"
fi

set +e
out7b="$(bash "${SCRIPT}" --markdown 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 2 ]] && grep -q "needs a FILE" <<<"${out7b}"; then
  ok "--markdown with no FILE argument exits 2 with 'needs a FILE'"
else
  bad "--markdown without a FILE did not behave as expected (rc=${rc})"; dump "${out7b}"
fi

set +e
out7c="$(env CHECK_UPSTREAM_FIXTURES="${tmp}/does-not-exist" bash "${SCRIPT}" 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 2 ]] && grep -q "fixtures dir not found" <<<"${out7c}"; then
  ok "a nonexistent CHECK_UPSTREAM_FIXTURES directory exits 2 with 'fixtures dir not found'"
else
  bad "nonexistent fixtures dir did not behave as expected (rc=${rc})"; dump "${out7c}"
fi

# =============================================================================
# 8. GITHUB_TOKEN argv-safety (commit c5576bb) — NOT testable through
#    fixtures, since FIXTURES mode returns from fetch() before curl/
#    subprocess is ever built (see the `if FIXTURES:` early-return at the top
#    of fetch()). Checked instead as a static grep assertion against the
#    script's source: the token must reach curl via `-K -` on stdin, and must
#    never be built into a literal `-H "Authorization: ..."` argv element.
# =============================================================================
echo "  -- 8. GITHUB_TOKEN argv-safety (static check; not reachable via fixtures) --"
if grep -qF 'cmd += ["-K", "-"]' "${SCRIPT}" \
  && grep -qF 'input=stdin_data' "${SCRIPT}" \
  && ! grep -Eq '\["-H", "Authorization: Bearer' "${SCRIPT}"; then
  ok "GITHUB_TOKEN still goes to curl via -K - on stdin; no literal -H \"Authorization: ...\" argv element"
else
  bad "GITHUB_TOKEN argv-safety pattern regressed (see commit c5576bb)"
fi

# =============================================================================
# 9. shellcheck
# =============================================================================
echo "  -- 9. shellcheck --"
SHELLCHECK_BIN="$(command -v shellcheck || true)"
if [[ -z "${SHELLCHECK_BIN}" && -x "${HOME}/.local/shellcheck/shellcheck.exe" ]]; then
  SHELLCHECK_BIN="${HOME}/.local/shellcheck/shellcheck.exe"
fi
if [[ -n "${SHELLCHECK_BIN}" ]]; then
  if "${SHELLCHECK_BIN}" "${SCRIPT}" "${BASH_SOURCE[0]}"; then
    ok "shellcheck clean (check-upstream.sh, this test)"
  else
    bad "shellcheck reported findings"
  fi
else
  echo "  SKIP shellcheck (not installed here)"
fi

echo
echo "test-check-upstream: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
