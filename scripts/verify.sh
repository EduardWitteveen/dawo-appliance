#!/usr/bin/env bash
#
# Full verification suite for dawo-appliance. Runs every automated check we have
# and prints one summary table, so "does it pass all tests?" has one answer.
# Requirement-to-test mapping: docs/testing.md.
#
# Needs Linux with Nix (flakes) and, for the boot tests, KVM. On the Windows +
# WSL development machine run it inside the WSL distro that has Nix:
#   wsl -d Ubuntu-24.04 -e bash -lc 'cd /mnt/c/git/dawo-appliance && bash scripts/verify.sh'
#
# Options (environment variables):
#   QUICK=1    only the fast checks (local dry-run suite + `nix flake check`)
#   FORCE=1    re-run boot tests even when Nix has a cached passing result
#              (`nix build --rebuild`); by default a cached pass counts
#   VERIFY_LOG_DIR=DIR  where per-check logs go (default: $TMPDIR/dawo-appliance-verify)
#   REPORT=1   also write the summary as Markdown to docs/verification-latest.md
#              (the file README.md links to; the ONLY way that file is updated)
#
# Nothing here writes to any disk other than the Nix store, the log dir and,
# with REPORT=1, docs/verification-latest.md in the working tree.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

LOG_DIR="${VERIFY_LOG_DIR:-${TMPDIR:-/tmp}/dawo-appliance-verify}"
mkdir -p "${LOG_DIR}"

declare -a results=()   # human lines
declare -a rows=()      # "status|name|detail" for the Markdown report
fail=0

run() {
  # run NAME COMMAND...  — runs the command, logs to $LOG_DIR/NAME.log, records
  # PASS/FAIL with the duration. Never aborts the suite.
  local name="$1"; shift
  local start=${SECONDS} line secs
  printf '==> %s\n' "${name}"
  if "$@" >"${LOG_DIR}/${name}.log" 2>&1; then
    secs=$((SECONDS - start))
    line="PASS  ${name}  (${secs}s)"
    rows+=("PASS|${name}|${secs}s")
  else
    secs=$((SECONDS - start))
    line="FAIL  ${name}  (${secs}s)  log: ${LOG_DIR}/${name}.log"
    rows+=("FAIL|${name}|${secs}s, see log")
    fail=1
  fi
  results+=("${line}")
  printf '    %s\n' "${line}"
}

skip() {
  results+=("SKIP  $1  ($2)")
  rows+=("SKIP|$1|$2")
  printf '==> %s\n    SKIP (%s)\n' "$1" "$2"
}

have() { command -v "$1" >/dev/null 2>&1; }

# fresh_build ATTR — build a flake attribute and force it to actually run even
# when Nix has a cached result (--rebuild). On a store that never built it,
# --rebuild refuses ("not valid, so checking is not possible"); a plain build is
# then already a fresh run. Used for the KVM probe and, with FORCE=1, the tests.
# Invoked indirectly through run(), hence the shellcheck exemption.
# shellcheck disable=SC2329
fresh_build() {
  local attr="$1" out
  if out="$(nix build ".#${attr}" --rebuild --no-link --no-warn-dirty 2>&1)"; then echo "${out}"; return 0; fi
  if grep -q "not valid, so checking is not possible" <<<"${out}"; then
    nix build ".#${attr}" --no-link --no-warn-dirty -L; return $?
  fi
  echo "${out}"; return 1
}

# --- fast, no privileges ----------------------------------------------------
run local-dryrun-suite bash tests/test-bootstrap-dryrun.sh
if have shellcheck; then
  run shellcheck-local shellcheck installer/bootstrap/dawo-appliance-bootstrap \
    tests/test-bootstrap-dryrun.sh scripts/status.sh scripts/verify.sh \
    scripts/screenshots.sh scripts/speed-check.sh
else
  skip shellcheck-local "shellcheck not on PATH; covered by nix flake check"
fi

if ! have nix; then
  skip nix-flake-check "nix not on PATH"
  skip iso-build "nix not on PATH"
  skip appliance-vm-build "nix not on PATH"
  skip test-installer-boot "nix not on PATH"
  skip test-appliance-boot "nix not on PATH"
else
  # evaluation + bootstrap-dryrun + shellcheck + workplace-parity
  run nix-flake-check nix flake check --no-warn-dirty

  if [[ "${QUICK:-0}" -eq 1 ]]; then
    skip iso-build "QUICK=1"
    skip appliance-vm-build "QUICK=1"
    skip test-installer-boot "QUICK=1"
    skip test-appliance-boot "QUICK=1"
  else
    run iso-build nix build .#installer-iso --no-link --no-warn-dirty
    run appliance-vm-build nix build .#appliance-vm --no-link --no-warn-dirty

    if [[ -w /dev/kvm ]]; then
      # Hardware acceleration inside the sandbox; a FAIL here means the boot
      # tests below still run, but under TCG emulation (minutes per boot).
      # Fix: bash scripts/speed-check.sh (APPLY=1).
      run kvm-in-sandbox fresh_build check-kvm
      if [[ "${FORCE:-0}" -eq 1 ]]; then
        run test-installer-boot fresh_build test-installer-boot
        run test-appliance-boot fresh_build test-appliance-boot
      else
        run test-installer-boot nix build .#test-installer-boot -L --no-link --no-warn-dirty
        run test-appliance-boot nix build .#test-appliance-boot -L --no-link --no-warn-dirty
      fi
    else
      skip test-installer-boot "/dev/kvm not writable (KVM needed)"
      skip test-appliance-boot "/dev/kvm not writable (KVM needed)"
    fi
  fi
fi

# --- summary -----------------------------------------------------------------
echo
echo "dawo-appliance verification summary ($(date -u +%Y-%m-%dT%H:%MZ), logs in ${LOG_DIR})"
echo "────────────────────────────────────────────────────────────"
printf '  %s\n' "${results[@]}"
echo "────────────────────────────────────────────────────────────"
if [[ "${fail}" -eq 0 ]]; then
  echo "RESULT: all executed checks passed"
else
  echo "RESULT: FAILURES — see the logs above"
fi

# --- Markdown report + duration history (REPORT=1) --------------------------
if [[ "${REPORT:-0}" -eq 1 ]]; then
  report="docs/verification-latest.md"
  history="docs/verification-history.csv"
  rev="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  now="$(date -u +%Y-%m-%dT%H:%MZ)"

  # Append this run's durations. One CSV, appended forever; averages below are
  # computed from it. Cached Nix results make some runs near-instant, so the
  # range matters as much as the mean.
  [[ -f "${history}" ]] || echo "date,rev,check,status,seconds" >"${history}"
  for row in "${rows[@]}"; do
    IFS='|' read -r st name detail <<<"${row}"
    if [[ "${st}" == "PASS" || "${st}" == "FAIL" ]]; then
      echo "${now},${rev},${name},${st},${detail%%s*}" >>"${history}"
    fi
  done

  # avg/min/max/n per check, from every recorded run (PASS and FAIL alike).
  stats() {
    awk -F, -v c="$1" 'NR>1 && $3==c { s+=$5; n++; if(min==""||$5<min)min=$5; if($5>max)max=$5 }
      END { if(n) printf "%d s avg (%d–%d s, n=%d)", s/n, min, max, n; else printf "—" }' "${history}"
  }

  # Boot timing from the appliance test, if that result exists.
  timing_md=""
  if have nix; then
    tres="$(nix build .#test-appliance-boot --no-link --print-out-paths --no-warn-dirty 2>/dev/null || true)"
    if [[ -n "${tres}" && -f "${tres}/timing.txt" ]]; then
      # Only "milestone<TAB>seconds" rows; systemd-analyze's free text is skipped.
      timing_md="$(awk -F'\t' 'NF==2 && $2 ~ /^[0-9]+$/ { printf "| %s | %s s |\n", $1, $2 }' "${tres}/timing.txt")"
    fi
  fi
  dirty=""
  if ! git diff --quiet HEAD 2>/dev/null || [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    dirty=" (working tree has uncommitted changes)"
  fi
  # Pins come from the manifest (the source of truth), not from a guess at
  # which flake.lock node comes first.
  nixpkgs_rev="$(grep -A4 '"nixpkgs": {' manifest/appliance-manifest.json | sed -n 's/.*"rev": "\([0-9a-f]*\)".*/\1/p' | head -1 | cut -c1-12)"
  dawo_rev="$(grep -A8 '"dawo_core": {' manifest/appliance-manifest.json | sed -n 's/.*"tag": "\([^"]*\)".*/\1/p' | head -1)"
  {
    echo "# Latest verification run"
    echo
    echo "Generated by \`REPORT=1 bash scripts/verify.sh\`; never edit by hand."
    echo "Requirement-to-test mapping: \`docs/testing.md\`."
    echo
    echo "- Date: ${now}"
    echo "- Repository: \`${rev}\`${dirty}"
    echo "- Host: $(uname -srm), KVM $([[ -w /dev/kvm ]] && echo available || echo unavailable)"
    echo "- Result: $([[ "${fail}" -eq 0 ]] && echo "**all executed checks passed**" || echo "**FAILURES**")"
    echo
    echo "| Check | Result | This run | All recorded runs (\`docs/verification-history.csv\`) |"
    echo "| --- | --- | --- | --- |"
    for row in "${rows[@]}"; do
      IFS='|' read -r st name detail <<<"${row}"
      case "${st}" in
        PASS) icon="✅ PASS" ;;
        FAIL) icon="❌ FAIL" ;;
        *)    icon="⏭️ SKIP" ;;
      esac
      echo "| \`${name}\` | ${icon} | ${detail} | $(stats "${name}") |"
    done
    echo
    echo "Durations depend on the Nix cache: a first run downloads several GB"
    echo "(the ISO and the Plasma closure); later runs reuse the store, and a"
    echo "cached passing test returns in seconds unless \`FORCE=1\`."
    if [[ -n "${timing_md}" ]]; then
      echo
      echo "### Boot timing of the installed host (test VM, software rendering, 4 vCPU)"
      echo
      echo "| Milestone | Seconds from power-on |"
      echo "| --- | --- |"
      echo "${timing_md}"
      echo
      echo "Real hardware with GPU acceleration is considerably faster; these are"
      echo "worst-case numbers from the headless test VM."
    fi
    echo
    echo "_Pins under test: nixpkgs \`${nixpkgs_rev}\`, DAWO-Core \`${dawo_rev}\` (all pins: \`manifest/appliance-manifest.json\`)._"
  } >"${report}"
  echo "report written: ${report}"
fi
exit "${fail}"
