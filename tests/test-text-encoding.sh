#!/usr/bin/env bash
# Every tracked text file is UTF-8 without BOM, with LF line endings and no
# NUL bytes (.gitattributes: LF only). Guards against editors or shells that
# write UTF-16 or CRLF (e.g. PowerShell redirection); twice on 2026-09-26 a
# file became UTF-16 and git started treating it as binary (#70, #80).
# No network, no Nix, no root.
#
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
checked=0
while IFS= read -r -d '' f; do
  case "$f" in
    *.png | *.jpg | *.jpeg | *.gif | *.ico | *.iso | *.qcow2 | *.pdf) continue ;;
  esac
  [ -f "$f" ] || continue
  checked=$((checked + 1))
  if [ "$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
    echo "FAIL: $f starts with a UTF-8 BOM"; fail=1
  fi
  if tr -d '\000' <"$f" | cmp -s - "$f"; then :; else
    echo "FAIL: $f contains NUL bytes (UTF-16 or binary?)"; fail=1; continue
  fi
  if grep -q $'\r' "$f"; then
    echo "FAIL: $f has CRLF line endings"; fail=1
  fi
  if ! iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1; then
    echo "FAIL: $f is not valid UTF-8"; fail=1
  fi
done < <(git ls-files -z)

if [ "$fail" -ne 0 ]; then
  echo "text-encoding: FAILED"
  exit 1
fi
echo "text-encoding: OK ($checked files are UTF-8, LF, no BOM, no NUL)"
