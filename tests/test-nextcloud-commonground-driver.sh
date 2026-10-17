#!/usr/bin/env bash
#
# Offline test for apps/nextcloud-commonground/deploy.sh and its
# configuration (#250). No root, no network, no Docker: only dry runs and
# file checks. Runs on Linux, WSL and Windows Git Bash (Python 3 as `python3`
# or `python`).
#
# Asserts:
#   1. every phase (park, docker, source, pull, apps, up, ready, enable, seed)
#      and --stop run in --dry-run without error and print what they would
#      do; an unknown phase fails; dry runs write nothing; park and docker
#      park the other compose projects; apps verifies every app's SHA-256;
#      enable enables all seven apps; seed runs both demo seeds;
#   2. every service our override pins has an image@sha256 equal to manifest
#      nextcloud_commonground.images, and its *_VERSION pins equal manifest
#      nextcloud_commonground.apps;
#   3. environment.toml names the same source rev as manifest
#      upstream.dossiq_compose, whose raw_url is at that rev, and the driver
#      that exists; the driver's enable order covers exactly the manifest's
#      apps; its project name and port equal the manifest's;
#   4. the dawo-docker unit is the same in this driver and Valtimo's (one
#      Docker Engine for the compose environments, D43).
#
# SPDX-License-Identifier: EUPL-1.2
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

pass=0; fail=0
ok() { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
PY="$(command -v python3 || command -v python)"

DRIVER=apps/nextcloud-commonground/deploy.sh
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
# The apps file as the host runner writes it, from the manifest.
"${PY}" - > "${tmp}/apps.txt" <<'EOF'
import json
apps = json.load(open("manifest/appliance-manifest.json", encoding="utf-8"))["nextcloud_commonground"]["apps"]
for i, a in apps.items():
    print(i, a["version"], a["url"], a["sha256"])
EOF
export NC_COMPOSE_URL=https://example.invalid/dossiq-compose.yaml NC_COMPOSE_SHA=00
export NC_OVERRIDE=environments/nextcloud-commonground/compose/override.yaml NC_APPS_FILE="${tmp}/apps.txt"
export NC_STATE_DIR="${tmp}/state"
mkdir -p "${NC_STATE_DIR}"
export DOCKER_URL=https://example.invalid/docker-1.tgz DOCKER_SHA=00 COMPOSE_URL=https://example.invalid/compose COMPOSE_SHA=00

echo "-- 1. dry runs --"
for p in park docker source pull apps up ready enable seed; do
  out="$(bash "${DRIVER}" --dry-run --phase "${p}" 2>&1)"; rc=$?
  if [[ "${rc}" -eq 0 ]] && grep -q '==>' <<<"${out}" && grep -q 'DRY-RUN' <<<"${out}"; then
    ok "--phase ${p} --dry-run prints its steps"
  else
    bad "--phase ${p} --dry-run (exit ${rc}): ${out}"
  fi
  case "${p}" in
    park|docker)
      if grep -q 'every compose project but dossiq-demo' <<<"${out}"; then ok "--phase ${p} parks the other compose projects"; else bad "--phase ${p} does not park the other compose projects"; fi ;;
    apps)
      n="$(grep -c 'sha256 must be [0-9a-f]\{64\}' <<<"${out}")"
      want="$(wc -l < "${tmp}/apps.txt" | tr -d ' ')"
      if [[ "${n}" -eq "${want}" ]]; then ok "--phase apps verifies all ${want} app tarballs"; else bad "--phase apps verifies ${n} of ${want} tarballs"; fi
      if grep -q 'run --rm --no-deps' <<<"${out}" && grep -q 'app-installer' <<<"${out}"; then ok "--phase apps unpacks in upstream's app-installer service"; else bad "--phase apps: no compose run of app-installer"; fi ;;
    enable)
      n="$(grep -c 'occ app:enable' <<<"${out}")"
      if [[ "${n}" -eq 7 ]]; then ok "--phase enable enables seven apps"; else bad "--phase enable enables ${n} apps"; fi ;;
    seed)
      if grep -q 'occ dossiq:demo:seed$' <<<"${out}" && grep -q 'occ pipelinq:demo:seed$' <<<"${out}"; then ok "--phase seed runs both demo seeds"; else bad "--phase seed: ${out}"; fi ;;
  esac
done
out="$(bash "${DRIVER}" --dry-run --stop 2>&1)"; rc=$?
if [[ "${rc}" -eq 0 ]] && grep -q 'compose' <<<"${out}"; then ok "--stop --dry-run stops the compose project"; else bad "--stop --dry-run (exit ${rc}): ${out}"; fi
if bash "${DRIVER}" --dry-run --phase nonsense >/dev/null 2>&1; then bad "an unknown phase must fail"; else ok "an unknown phase fails"; fi
if [[ -z "$(ls -A "${NC_STATE_DIR}")" ]]; then ok "dry runs write nothing"; else bad "dry runs wrote into ${NC_STATE_DIR}"; fi
out="$(bash apps/valtimo/deploy.sh --dry-run --phase park 2>&1)"
if grep -q 'every compose project but gzac-docker-compose' <<<"${out}"; then ok "Valtimo's park phase parks the other compose projects too"; else bad "Valtimo's park does not park other compose projects: ${out}"; fi

echo "-- 2. override pins = manifest --"
res="$("${PY}" - <<'EOF'
import json, re
m = json.load(open("manifest/appliance-manifest.json", encoding="utf-8"))["nextcloud_commonground"]
txt = open("environments/nextcloud-commonground/compose/override.yaml", encoding="utf-8").read()
found = dict(re.findall(r"^  ([a-z0-9-]+):\n    image: (\S+)$", txt, re.M))
bad = []
for svc, pin in m["images"].items():
    want = pin["image"] + "@" + pin["digest"]
    if found.get(svc) != want:
        bad.append(f"{svc}: override {found.get(svc)!r}, manifest {want!r}")
extra = sorted(set(found) - set(m["images"]))
if extra: bad.append("in the override but not in the manifest: " + ", ".join(extra))
versions = dict(re.findall(r'^      ([A-Z]+)_VERSION: "([^"]+)"$', txt, re.M))
if not versions: bad.append("no *_VERSION pins in the override")
for app, v in versions.items():
    want = m["apps"].get(app.lower(), {}).get("version")
    if v != want:
        bad.append(f"{app}_VERSION: override {v!r}, manifest {want!r}")
for app, a in m["apps"].items():
    if not re.fullmatch(r"[0-9a-f]{64}", a["sha256"]): bad.append(f"{app}: sha256 is not 64 hex")
    if f"/v{a['version']}/{app}-{a['version']}.tar.gz" not in a["url"]: bad.append(f"{app}: url does not name version {a['version']}")
print("OK %d images, %d versions" % (len(m["images"]), len(versions)) if not bad else "\n".join(bad))
EOF
)"
if [[ "${res}" == OK* ]]; then ok "override equals manifest nextcloud_commonground (${res#OK })"; else bad "override vs manifest: ${res}"; fi

echo "-- 3. environment.toml, driver constants --"
ENVTOML=environments/nextcloud-commonground/environment.toml
rev_env="$(sed -n 's/^rev = "\([0-9a-f]\{40\}\)"$/\1/p' "${ENVTOML}")"
man() { "${PY}" -c "import json,sys; m=json.load(open('manifest/appliance-manifest.json', encoding='utf-8')); print(eval(sys.argv[1]))" "$1"; }
rev_man="$(man 'm["upstream"]["dossiq_compose"]["rev"]')"
if [[ -n "${rev_env}" && "${rev_env}" == "${rev_man}" ]]; then ok "source.rev equals manifest upstream.dossiq_compose.rev"; else bad "source.rev '${rev_env}' vs manifest '${rev_man}'"; fi
raw="$(man 'm["upstream"]["dossiq_compose"]["raw_url"]')"
if [[ "${raw}" == *"/${rev_man}/dossiq-compose.yaml" ]]; then ok "raw_url is the file at the pinned rev"; else bad "raw_url '${raw}' is not at ${rev_man}"; fi
drv="$(sed -n 's/^driver = "\(.*\)"$/\1/p' "${ENVTOML}")"
if [[ -f "${drv}" ]]; then ok "deploy.driver ${drv} exists"; else bad "deploy.driver '${drv}' missing"; fi
order="$(sed -n 's/^ENABLE_ORDER=(\(.*\))$/\1/p' "${DRIVER}" | tr ' ' '\n' | sort | tr '\n' ' ')"
apps="$(man '" ".join(sorted(m["nextcloud_commonground"]["apps"]))') "
if [[ "${order}" == "${apps}" ]]; then ok "ENABLE_ORDER covers exactly the manifest's apps"; else bad "ENABLE_ORDER '${order}' vs manifest '${apps}'"; fi
if [[ "$(sed -n 's/^ENABLE_ORDER=(\([a-z]*\) .*/\1/p' "${DRIVER}")" == openregister ]]; then ok "OpenRegister is enabled first"; else bad "OpenRegister is not first in ENABLE_ORDER"; fi
proj="$(sed -n 's/^PROJECT="\(.*\)"$/\1/p' "${DRIVER}")"; port="$(sed -n 's/^PORT=\([0-9]*\).*/\1/p' "${DRIVER}")"
if [[ "${proj}" == "$(man 'm["nextcloud_commonground"]["compose"]["project"]')" && "${port}" == "$(man 'm["nextcloud_commonground"]["compose"]["port"]')" ]]; then
  ok "project ${proj} and port ${port} equal the manifest"
else
  bad "project '${proj}' / port '${port}' differ from the manifest"
fi
if grep -q "localhost:${port}/" "${ENVTOML}"; then ok "url and health.url use port ${port}"; else bad "environment.toml does not use port ${port}"; fi

echo "-- 4. one Docker Engine --"
unit() { sed -n '/# BEGIN dawo-docker.service/,/# END dawo-docker.service/p' "$1"; }
u1="$(unit "${DRIVER}")"; u2="$(unit apps/valtimo/deploy.sh)"
if [[ -n "${u1}" && "${u1}" == "${u2}" ]]; then ok "the dawo-docker unit is the same in both drivers"; else bad "the dawo-docker unit differs between the drivers"; fi

echo
echo "test-nextcloud-commonground-driver: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
