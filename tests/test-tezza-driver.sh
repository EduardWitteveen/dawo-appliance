#!/usr/bin/env bash
#
# Offline test for apps/tezza/deploy.sh and its configuration (#261).
# No root, no network, no Docker: only dry runs and file checks. Runs on
# Linux, WSL and Windows Git Bash (Python 3 as `python3` or `python`).
#
# Asserts:
#   1. every phase (park, docker, source, pull, up, ready, setup) and --stop run in
#      --dry-run without error and print what they would do; an unknown
#      phase fails;
#   2. every service our override pins has
#      an image@sha256 equal to manifest tezza.images (digest and tag);
#   3. environments/tezza/environment.toml names the same source rev as
#      manifest upstream.tezza_packaging and the driver that exists.
#
# SPDX-License-Identifier: EUPL-1.2
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

pass=0; fail=0
ok() { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
PY="$(command -v python3 || command -v python)"

DRIVER=apps/tezza/deploy.sh
export TZ_REPO=https://example.invalid/gzac TZ_REV=0123456789abcdef0123456789abcdef01234567
TZ_STATE_DIR="$(mktemp -d)"
export TZ_OVERRIDE=environments/tezza/compose/override.yaml TZ_STATE_DIR
export DOCKER_URL=https://example.invalid/docker-1.tgz DOCKER_SHA=00 COMPOSE_URL=https://example.invalid/compose COMPOSE_SHA=00

echo "-- 1. dry runs --"
for p in park docker source pull up ready setup; do
  out="$(bash "${DRIVER}" --dry-run --phase "${p}" 2>&1)"; rc=$?
  if [[ "${rc}" -eq 0 ]] && grep -q '==>' <<<"${out}" && grep -q 'DRY-RUN' <<<"${out}"; then
    ok "--phase ${p} --dry-run prints its steps"
  else
    bad "--phase ${p} --dry-run (exit ${rc}): ${out}"
  fi
done
out="$(bash "${DRIVER}" --dry-run --stop 2>&1)"; rc=$?
if [[ "${rc}" -eq 0 ]] && grep -q 'compose' <<<"${out}"; then ok "--stop --dry-run stops the compose project"; else bad "--stop --dry-run (exit ${rc}): ${out}"; fi
if bash "${DRIVER}" --dry-run --phase nonsense >/dev/null 2>&1; then bad "an unknown phase must fail"; else ok "an unknown phase fails"; fi
if [[ -z "$(ls -A "${TZ_STATE_DIR}")" ]]; then ok "dry runs write nothing"; else bad "dry runs wrote into ${TZ_STATE_DIR}"; fi
rm -rf "${TZ_STATE_DIR}"

echo "-- 2. override pins = manifest --"
res="$("${PY}" - <<'EOF'
import json, re
m = json.load(open("manifest/appliance-manifest.json", encoding="utf-8"))["tezza"]["images"]
txt = open("environments/tezza/compose/override.yaml", encoding="utf-8").read()
found = dict(re.findall(r"^  ([a-z0-9-]+):\n    image: (\S+)$", txt, re.M))
bad = []
for svc, pin in m.items():
    want = pin["image"] + "@" + pin["digest"]
    if found.get(svc) != want:
        bad.append(f"{svc}: override {found.get(svc)!r}, manifest {want!r}")
extra = sorted(set(found) - set(m))
if extra: bad.append("in the override but not in the manifest: " + ", ".join(extra))
print("OK %d" % len(m) if not bad else "\n".join(bad))
EOF
)"
if [[ "${res}" == OK* ]]; then ok "override images equal manifest tezza.images (${res#OK })"; else bad "override vs manifest: ${res}"; fi

echo "-- 3. environment.toml --"
rev_env="$(sed -n 's/^rev = "\([0-9a-f]\{40\}\)"$/\1/p' environments/tezza/environment.toml)"
rev_man="$("${PY}" -c 'import json; print(json.load(open("manifest/appliance-manifest.json", encoding="utf-8"))["upstream"]["tezza_packaging"]["rev"])')"
if [[ -n "${rev_env}" && "${rev_env}" == "${rev_man}" ]]; then ok "source.rev equals manifest upstream.tezza_packaging.rev"; else bad "source.rev '${rev_env}' vs manifest '${rev_man}'"; fi
drv="$(sed -n 's/^driver = "\(.*\)"$/\1/p' environments/tezza/environment.toml)"
if [[ -f "${drv}" ]]; then ok "deploy.driver ${drv} exists"; else bad "deploy.driver '${drv}' missing"; fi

echo "-- 4. shared Docker Engine --"
if diff <(sed -n '/# BEGIN dawo-docker.service/,/# END dawo-docker.service/p' apps/tezza/deploy.sh)         <(sed -n '/# BEGIN dawo-docker.service/,/# END dawo-docker.service/p' apps/valtimo/deploy.sh) >/dev/null; then
  ok "the dawo-docker unit is the same as Valtimo's"
else
  bad "the dawo-docker unit differs from apps/valtimo/deploy.sh"
fi
echo
echo "test-tezza-driver: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
