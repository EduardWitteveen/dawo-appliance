#!/usr/bin/env bash
#
# status.sh — session orientation helper for dawo-appliance.
#
# Prints "where were we" at the start of a work session: the current slice and
# next step (from docs/STATUS.md), the blocking open questions, a few live
# checks (manifest checksum + dry-run tests), and recently changed files.
#
# Self-contained: no network, no Nix, no root, no git required. Safe to run on
# the /mnt/c path where git/Nix do not work (see docs/open-questions.md OQ-1).
#
# Usage:
#   bash scripts/status.sh            # full report (runs the dry-run tests)
#   bash scripts/status.sh --no-test  # skip the test run (faster)
#
set -euo pipefail

# Resolve the repository root from this script's location, so it works from
# any working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

RUN_TESTS=1
for arg in "$@"; do
  case "$arg" in
    --no-test) RUN_TESTS=0 ;;
    -h | --help)
      sed -n '3,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "status.sh: unknown argument '$arg' (try --help)" >&2
      exit 2
      ;;
  esac
done

# Colour only when writing to a terminal.
if [[ -t 1 ]]; then
  B=$'\033[1m'; DIM=$'\033[2m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; X=$'\033[0m'
else
  B=""; DIM=""; G=""; R=""; Y=""; X=""
fi

hr() { printf '%s\n' "${DIM}────────────────────────────────────────────────────────${X}"; }

printf '\n%s== dawo-appliance — session status ==%s\n' "$B" "$X"
printf '%sExperimental, unofficial appliance. Not an official DAWO/Mijn Bureau/BZK build.%s\n' "$DIM" "$X"
hr

# --- Handoff: Now / Next, lifted from docs/STATUS.md ------------------------
STATUS_DOC="docs/STATUS.md"
if [[ -f "$STATUS_DOC" ]]; then
  # Print the body of a "## <Heading>" section until the next "## ".
  section() {
    awk -v want="## $1" '
      $0 == want { inside = 1; next }
      /^## / { inside = 0 }
      inside { print }
    ' "$STATUS_DOC"
  }
  printf '%sNow:%s\n' "$B" "$X"
  section "Now" | sed '/^[[:space:]]*$/d;s/^/  /'
  printf '\n%sNext:%s\n' "$B" "$X"
  section "Next" | sed '/^[[:space:]]*$/d;s/^/  /'
else
  printf '%s(no %s found — create it as the session handoff)%s\n' "$Y" "$STATUS_DOC" "$X"
fi
hr

# --- Blocking open questions ------------------------------------------------
printf '%sBlocking open questions:%s\n' "$B" "$X"
if [[ -f docs/open-questions.md ]]; then
  if grep -q 'BLOCKING' docs/open-questions.md; then
    grep -E '^## OQ.*BLOCKING' docs/open-questions.md \
      | sed -E 's/^## /  • /; s/`//g'
  else
    printf '  %snone%s\n' "$G" "$X"
  fi
else
  printf '  %sdocs/open-questions.md missing%s\n' "$Y" "$X"
fi
hr

# --- Live checks ------------------------------------------------------------
printf '%sLive checks:%s\n' "$B" "$X"

# Manifest checksum.
if [[ -f manifest/appliance-manifest.json && -f manifest/appliance-manifest.json.sha256 ]]; then
  if (cd manifest && sha256sum --check --status appliance-manifest.json.sha256); then
    printf '  %s✓%s manifest checksum matches\n' "$G" "$X"
  else
    printf '  %s✗%s manifest checksum MISMATCH — regenerate (cd manifest && sha256sum ...)\n' "$R" "$X"
  fi
else
  printf '  %s—%s manifest or its .sha256 not found\n' "$Y" "$X"
fi

# Dry-run test suite.
if [[ "$RUN_TESTS" -eq 1 && -f tests/test-bootstrap-dryrun.sh ]]; then
  if test_out="$(bash tests/test-bootstrap-dryrun.sh 2>&1)"; then
    summary="$(printf '%s\n' "$test_out" | grep -E ' passed,| failed' | tail -1)"
    printf '  %s✓%s dry-run tests: %s\n' "$G" "$X" "${summary:-passed}"
  else
    printf '  %s✗%s dry-run tests FAILED:\n' "$R" "$X"
    printf '%s\n' "$test_out" | sed 's/^/      /'
  fi
elif [[ "$RUN_TESTS" -eq 0 ]]; then
  printf '  %s—%s dry-run tests skipped (--no-test)\n' "$DIM" "$X"
else
  printf '  %s—%s tests/test-bootstrap-dryrun.sh not found\n' "$Y" "$X"
fi
hr

# --- Recently changed files -------------------------------------------------
# No git on this path (OQ-1), so use modification time as the signal.
printf '%sRecently changed (by mtime):%s\n' "$B" "$X"
find . \
  -path ./.git -prune -o \
  -type f \
  ! -name '*.lock' \
  -printf '%T@ %p\n' 2>/dev/null \
  | sort -rn | head -8 \
  | while read -r _ path; do printf '  %s\n' "${path#./}"; done
hr

printf '%sEdit docs/STATUS.md at the end of a session to keep this useful.%s\n\n' "$DIM" "$X"
