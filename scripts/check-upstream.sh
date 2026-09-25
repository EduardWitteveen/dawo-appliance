#!/usr/bin/env bash
#
# check-upstream.sh — has anything happened upstream since we pinned it?
#
# Compares the pins in manifest/appliance-manifest.json and flake.lock
# (nixpkgs, disko, dawo-core) against upstream and prints a compact table:
#   component | pinned | latest | status | link
# status is one of UP TO DATE, NEWER AVAILABLE, MOVED, EOL, UNKNOWN.
#
# Read-only and re-entrant: it only issues HTTP GETs (curl, per-request
# timeout) and never writes to the repository unless --markdown is given.
# Unauthenticated GitHub API calls are rate-limited (60/h); a 403/429 marks the
# row UNKNOWN and the check continues. Set GITHUB_TOKEN to raise the limit (the
# token is only sent to api.github.com and never printed).
#
# Usage:
#   bash scripts/check-upstream.sh                  # table on stdout
#   bash scripts/check-upstream.sh --json           # machine-readable JSON
#   bash scripts/check-upstream.sh --markdown FILE  # also write a report
#                                                   # (e.g. docs/upstream/latest-check.md;
#                                                   # do not commit it)
#
# Environment:
#   CHECK_UPSTREAM_TIMEOUT=20       seconds per request
#   CHECK_UPSTREAM_FIXTURES=DIR     offline mode: read canned responses from
#                                   DIR/<key>.{json,txt} (a DIR/<key>.status
#                                   file holding e.g. 403 simulates an error)
#   CHECK_UPSTREAM_NOW=YYYY-MM-DD   reference date for the EOL heuristic
#
# Requires: bash, curl, python3 (no jq). Works in Windows Git Bash and WSL.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() { sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

FORMAT=table
MARKDOWN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) FORMAT=json ;;
    --markdown)
      [ $# -ge 2 ] || { echo "error: --markdown needs a FILE" >&2; exit 2; }
      MARKDOWN="$2"
      shift
      ;;
    -h | --help) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

for tool in curl python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool not found" >&2; exit 1; }
done

# On Windows Git Bash, python3 is a native Windows binary: hand it Windows paths.
winpath() {
  if [ -n "$1" ] && command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

if [ -n "$MARKDOWN" ]; then
  case "$MARKDOWN" in /*) ;; *) MARKDOWN="$PWD/$MARKDOWN" ;; esac
fi
FIXTURES="${CHECK_UPSTREAM_FIXTURES:-}"
if [ -n "$FIXTURES" ]; then
  [ -d "$FIXTURES" ] || { echo "error: fixtures dir not found: $FIXTURES" >&2; exit 2; }
  FIXTURES="$(cd "$FIXTURES" && pwd)"
fi

CU_ROOT="$(winpath "$ROOT")" \
  CU_FORMAT="$FORMAT" \
  CU_MARKDOWN="$(winpath "$MARKDOWN")" \
  CU_FIXTURES="$(winpath "$FIXTURES")" \
  CU_TIMEOUT="${CHECK_UPSTREAM_TIMEOUT:-20}" \
  CU_NOW="${CHECK_UPSTREAM_NOW:-}" \
  python3 - <<'PY'
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.environ["CU_ROOT"]
FORMAT = os.environ["CU_FORMAT"]
MARKDOWN = os.environ["CU_MARKDOWN"]
FIXTURES = os.environ["CU_FIXTURES"]
TIMEOUT = os.environ["CU_TIMEOUT"]
NOW = (dt.datetime.strptime(os.environ["CU_NOW"], "%Y-%m-%d").replace(tzinfo=dt.timezone.utc)
       if os.environ["CU_NOW"] else dt.datetime.now(dt.timezone.utc))

# sha256 of the normalised "## Notice" section of DAWO-Core's README (main),
# recorded 2026-09-25 (the move to Codeberg). A different hash means the
# notice changed: the project may have moved again.
NOTICE_BASELINE = "4559ec536e9222b1749001e364d676b5e34db063fc20f3b3f8ffe6479060f87f"

CODEBERG = "https://codeberg.org"
CB_API = CODEBERG + "/api/v1/repos/DAWO/DAWO-Core"
GH_API = "https://api.github.com/repos"
GH_RAW = "https://raw.githubusercontent.com"


class FetchError(Exception):
    pass


def fetch(key, url):
    """Return the body of url as text; raise FetchError on any failure."""
    if FIXTURES:
        st = os.path.join(FIXTURES, key + ".status")
        if os.path.exists(st):
            raise FetchError("HTTP " + open(st).read().strip() + " (fixture)")
        for ext in (".json", ".txt"):
            p = os.path.join(FIXTURES, key + ext)
            if os.path.exists(p):
                with open(p, encoding="utf-8") as f:
                    return f.read()
        raise FetchError("no fixture " + key)
    # Note: some curl builds (Git for Windows 8.8.0) fail on -w '%{http_code}',
    # so the status is read from the dumped headers instead.
    fd, hdr = tempfile.mkstemp()
    os.close(fd)
    cmd = ["curl", "-sS", "-L", "--max-time", TIMEOUT, "-D", hdr,
           "-H", "User-Agent: dawo-appliance-check-upstream"]
    if url.startswith("https://api.github.com/"):
        cmd += ["-H", "Accept: application/vnd.github+json"]
        if os.environ.get("GITHUB_TOKEN"):
            cmd += ["-H", "Authorization: Bearer " + os.environ["GITHUB_TOKEN"]]
    try:
        p = subprocess.run(cmd + [url], capture_output=True)
        with open(hdr, encoding="latin-1") as f:
            headers = f.read()
    finally:
        os.unlink(hdr)
    codes = re.findall(r"^HTTP/\S+\s+(\d{3})", headers, re.M)
    code = int(codes[-1]) if codes else 0
    if p.returncode != 0 and not codes:
        raise FetchError("curl exit %d" % p.returncode)
    if code in (403, 429) and "x-ratelimit-remaining: 0" in headers.lower():
        raise FetchError("GitHub rate limit")
    if code != 200:
        raise FetchError("HTTP %d" % code)
    return p.stdout.decode("utf-8", "replace")


def fetch_json(key, url):
    try:
        return json.loads(fetch(key, url))
    except ValueError as e:
        raise FetchError("bad JSON: %s" % e)


def vkey(tag):
    m = re.match(r"^v?(\d+)\.(\d+)\.(\d+)(?:\+k3s(\d+))?$", tag)
    return tuple(int(x or 0) for x in m.groups()) if m else None


def parse_date(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def short(rev):
    return rev[:7] if rev else "?"


rows = []


def row(component, pinned, latest, status, link, note=""):
    rows.append({"component": component, "pinned": pinned, "latest": latest,
                 "status": status, "link": link, "note": note})


def unknown(component, pinned, link, err):
    row(component, pinned, "?", "UNKNOWN", link, str(err))


def newer(pinned, latest):
    return "UP TO DATE" if pinned == latest else "NEWER AVAILABLE"


with open(os.path.join(ROOT, "manifest", "appliance-manifest.json"), encoding="utf-8") as f:
    M = json.load(f)
with open(os.path.join(ROOT, "flake.lock"), encoding="utf-8") as f:
    LOCK = json.load(f)


def lock_node(lock, name):
    return lock["nodes"][lock["nodes"][lock["root"]]["inputs"][name]]["locked"]


DC = M["upstream"]["dawo_core"]
dc_lock = lock_node(LOCK, "dawo-core")
dc_tag = (dc_lock.get("ref") or "").replace("refs/tags/", "") or DC["tag"]
nixpkgs_ref = M["nix"]["nixpkgs"]["ref"]
nixpkgs_rev = lock_node(LOCK, "nixpkgs")["rev"]
disko_rev = lock_node(LOCK, "disko")["rev"]

# --- DAWO-Core: newest version tag / release --------------------------------
dc_newest = None
try:
    tags = fetch_json("dawo_tags", CB_API + "/tags?limit=50")
    vtags = sorted((t["name"] for t in tags if vkey(t["name"])), key=vkey)
    dc_newest = vtags[-1] if vtags else None
    pre = ""
    try:
        rels = {r["tag_name"]: r for r in fetch_json("dawo_releases", CB_API + "/releases?limit=20")}
        if dc_newest in rels and rels[dc_newest].get("prerelease"):
            pre = " (pre-release)"
    except FetchError:
        pass
    status = "UP TO DATE" if vkey(dc_newest) <= vkey(dc_tag) else "NEWER AVAILABLE"
    row("dawo-core tag", dc_tag, (dc_newest or "?") + pre, status,
        CODEBERG + "/DAWO/DAWO-Core/releases/tag/" + (dc_newest or dc_tag))
except FetchError as e:
    unknown("dawo-core tag", dc_tag, CODEBERG + "/DAWO/DAWO-Core/tags", e)

# --- DAWO-Core: main head (informational: we pin tags) ----------------------
try:
    b = fetch_json("dawo_main", CB_API + "/branches/main")
    head, when = b["commit"]["id"], b["commit"]["timestamp"][:10]
    row("dawo-core main", "%s (%s)" % (short(dc_lock["rev"]), DC.get("commit_date", "?")),
        "%s (%s)" % (short(head), when), newer(dc_lock["rev"], head),
        CODEBERG + "/DAWO/DAWO-Core/commits/branch/main",
        "" if head == dc_lock["rev"] else "untagged commits on main")
except FetchError as e:
    unknown("dawo-core main", short(dc_lock["rev"]), CODEBERG + "/DAWO/DAWO-Core", e)

# --- DAWO-Core: README "Notice" (moved) section ------------------------------
try:
    readme = fetch("dawo_readme", CODEBERG + "/DAWO/DAWO-Core/raw/branch/main/README.md")
    m = re.search(r"^## Notice\s*$(.*?)(?=^## |\Z)", readme, re.M | re.S)
    if not m:
        row("dawo-core notice", NOTICE_BASELINE[:12], "(section gone)", "MOVED",
            CODEBERG + "/DAWO/DAWO-Core", "README Notice section missing")
    else:
        text = "\n".join(l.rstrip() for l in m.group(1).strip().splitlines() if l.strip())
        h = hashlib.sha256(text.encode("utf-8")).hexdigest()
        row("dawo-core notice", NOTICE_BASELINE[:12], h[:12],
            "UP TO DATE" if h == NOTICE_BASELINE else "MOVED",
            CODEBERG + "/DAWO/DAWO-Core#notice",
            "" if h == NOTICE_BASELINE else "README Notice changed: " + text.splitlines()[0][:100])
except FetchError as e:
    unknown("dawo-core notice", NOTICE_BASELINE[:12], CODEBERG + "/DAWO/DAWO-Core", e)

# --- nixpkgs: head of the pinned branch + EOL heuristic ----------------------
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


try:
    c = fetch_json("nixpkgs_head", "%s/NixOS/nixpkgs/commits/%s" % (GH_API, nixpkgs_ref))
    head, when = c["sha"], parse_date(c["commit"]["committer"]["date"])
    idle = (NOW - when).days
    newer_branch = None
    for nb in next_branches(nixpkgs_ref):
        try:
            fetch_json("nixpkgs_branch_" + nb, "%s/NixOS/nixpkgs/branches/%s" % (GH_API, nb))
            newer_branch = nb
        except FetchError:
            break
    if idle > 30 and newer_branch:
        status, note = "EOL", "no commits for %d days; %s exists" % (idle, newer_branch)
    else:
        status = newer(nixpkgs_rev, head)
        note = ("%s exists" % newer_branch) if newer_branch else ""
    row("nixpkgs " + nixpkgs_ref, short(nixpkgs_rev),
        "%s (%s)" % (short(head), when.date()), status,
        "https://github.com/NixOS/nixpkgs/commits/" + nixpkgs_ref, note)
except FetchError as e:
    unknown("nixpkgs " + nixpkgs_ref, short(nixpkgs_rev),
            "https://github.com/NixOS/nixpkgs/commits/" + nixpkgs_ref, e)

# --- nixpkgs + disko as pinned by DAWO-Core's newest tag (we follow those) ---
ref_tag = dc_newest or dc_tag
link = "%s/DAWO/DAWO-Core/src/tag/%s/flake.lock" % (CODEBERG, ref_tag)
try:
    dl = fetch_json("dawo_flake_lock", "%s/DAWO/DAWO-Core/raw/tag/%s/flake.lock" % (CODEBERG, ref_tag))
    for name, ours in (("nixpkgs", nixpkgs_rev), ("disko", disko_rev)):
        theirs = lock_node(dl, name)["rev"]
        row("%s (dawo-core %s pin)" % (name, ref_tag), short(ours), short(theirs),
            newer(ours, theirs), link)
except (FetchError, KeyError) as e:
    for name, ours in (("nixpkgs", nixpkgs_rev), ("disko", disko_rev)):
        unknown("%s (dawo-core %s pin)" % (name, ref_tag), short(ours), link, e)

# --- mijn-bureau-infra: main head, commits since our rev, image tags ---------
MB = M["upstream"]["mijn_bureau_infra"]
mb_rev = MB["rev"]
MB_GH = "MinBZK/mijn-bureau-infra"
CONTAINER = "helmfile/environments/default/container.yaml.gotmpl"


def parse_images(text):
    """Map service -> repository:tag from the two-level container.yaml.gotmpl."""
    out, cur, repo = {}, None, None
    for line in text.splitlines():
        m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if m:
            cur, repo = m.group(1), None
            continue
        m = re.match(r"^    (repository|tag):\s*\"?([^\"#\s]*)\"?", line)
        if m and cur:
            if m.group(1) == "repository":
                repo = m.group(2)
            else:
                out[cur] = "%s:%s" % (repo or "?", m.group(2))
    return out


try:
    c = fetch_json("mbi_head", "%s/%s/commits/main" % (GH_API, MB_GH))
    head, when = c["sha"], c["commit"]["committer"]["date"][:10]
    note = ""
    if head != mb_rev:
        try:
            cmp = fetch_json("mbi_compare", "%s/%s/compare/%s...%s" % (GH_API, MB_GH, mb_rev, head))
            note = "%d commits since pin" % cmp.get("ahead_by", 0)
        except FetchError as e:
            note = "compare: %s" % e
    row("mijn-bureau-infra main", "%s (%s)" % (short(mb_rev), MB.get("commit_date", "?")),
        "%s (%s)" % (short(head), when), newer(mb_rev, head),
        "https://github.com/%s/compare/%s...%s" % (MB_GH, short(mb_rev), short(head)), note)
    if head != mb_rev:
        try:
            old = parse_images(fetch("mbi_container_pinned", "%s/%s/%s/%s" % (GH_RAW, MB_GH, mb_rev, CONTAINER)))
            new = parse_images(fetch("mbi_container_head", "%s/%s/%s/%s" % (GH_RAW, MB_GH, head, CONTAINER)))
            for svc in sorted(set(old) | set(new)):
                if old.get(svc) != new.get(svc):
                    row("  image " + svc, old.get(svc, "(none)"), new.get(svc, "(removed)"),
                        "NEWER AVAILABLE", "https://github.com/%s/blob/%s/%s" % (MB_GH, short(head), CONTAINER))
        except FetchError as e:
            unknown("  images", "-", "https://github.com/%s/blob/main/%s" % (MB_GH, CONTAINER), e)
except FetchError as e:
    unknown("mijn-bureau-infra main", short(mb_rev), "https://github.com/" + MB_GH, e)

# --- K3s: newest stable release (and newest patch of our minor) --------------
k3s_tag = M["kubernetes"]["version"]["tag"]
try:
    rels = fetch_json("k3s_releases", GH_API + "/k3s-io/k3s/releases?per_page=100")
    stable = sorted((r["tag_name"] for r in rels
                     if not r.get("prerelease") and not r.get("draft") and vkey(r["tag_name"])), key=vkey)
    ours = vkey(k3s_tag)
    newest = stable[-1]
    same_minor = [t for t in stable if vkey(t)[:2] == ours[:2]]
    latest = newest
    if same_minor and same_minor[-1] != newest and vkey(same_minor[-1]) > ours:
        latest += " (%s in our minor)" % same_minor[-1]
    row("k3s", k3s_tag, latest, "UP TO DATE" if vkey(newest) <= ours else "NEWER AVAILABLE",
        "https://github.com/k3s-io/k3s/releases/tag/" + newest)
except (FetchError, IndexError) as e:
    unknown("k3s", k3s_tag, "https://github.com/k3s-io/k3s/releases", e)

# --- Ubuntu noble cloud image ---------------------------------------------
serial = M["vm"]["image"]["serial"]
UB = "https://cloud-images.ubuntu.com/releases/noble/"
try:
    serials = sorted(set(re.findall(r"release-(\d{8})", fetch("ubuntu_index", UB))))
    latest = serials[-1]
    row("ubuntu noble image", serial, latest, "UP TO DATE" if latest <= serial else "NEWER AVAILABLE",
        UB + "release-" + latest + "/")
except (FetchError, IndexError) as e:
    unknown("ubuntu noble image", serial, UB, e)

# --- cert-manager (upstream pins it; supported = the two newest minors) ------
cm = M["mijn_bureau"]["tooling"]["cert_manager"]
try:
    rels = fetch_json("certmanager_releases", GH_API + "/cert-manager/cert-manager/releases?per_page=50")
    stable = sorted((r["tag_name"] for r in rels
                     if not r.get("prerelease") and not r.get("draft") and vkey(r["tag_name"])), key=vkey)
    newest = stable[-1]
    minors = sorted({vkey(t)[:2] for t in stable})
    if vkey(cm)[:2] not in minors[-2:] and vkey(cm) < vkey(newest):
        status, note = "EOL", "only the two newest minors are supported (pinned upstream)"
    else:
        status, note = ("UP TO DATE" if vkey(newest) <= vkey(cm) else "NEWER AVAILABLE"), ""
    row("cert-manager (upstream pin)", cm, newest, status,
        "https://github.com/cert-manager/cert-manager/releases/tag/" + newest, note)
except (FetchError, IndexError) as e:
    unknown("cert-manager (upstream pin)", cm, "https://github.com/cert-manager/cert-manager/releases", e)

# --- output --------------------------------------------------------------
summary = {}
for r in rows:
    summary[r["status"]] = summary.get(r["status"], 0) + 1
stamp = NOW.strftime("%Y-%m-%d %H:%M UTC")
cols = ("component", "pinned", "latest", "status", "link")


def table():
    w = {c: max(len(c), *(len(r[c]) for r in rows)) for c in cols[:-1]}
    lines = [" | ".join(c.ljust(w[c]) for c in cols[:-1]) + " | link",
             "-+-".join("-" * w[c] for c in cols[:-1]) + "-+-----"]
    for r in rows:
        lines.append(" | ".join(r[c].ljust(w[c]) for c in cols[:-1]) + " | " + r["link"])
    notes = ["  - %s: %s" % (r["component"].strip(), r["note"]) for r in rows if r["note"]]
    if notes:
        lines += ["", "Notes:"] + notes
    lines += ["", "Summary: " + ", ".join("%s %d" % kv for kv in sorted(summary.items()))]
    return "\n".join(lines)


def markdown():
    out = ["# Upstream check", "",
           "Generated by `scripts/check-upstream.sh` on %s%s. Not committed." %
           (stamp, " (fixtures)" if FIXTURES else ""), "",
           "| Component | Pinned | Latest | Status | Link | Note |",
           "|---|---|---|---|---|---|"]
    for r in rows:
        cells = [r["component"].strip(), "`%s`" % r["pinned"], "`%s`" % r["latest"],
                 "**%s**" % r["status"] if r["status"] != "UP TO DATE" else r["status"],
                 "[link](%s)" % r["link"], r["note"]]
        out.append("| " + " | ".join(c.replace("|", "\\|") for c in cells) + " |")
    return "\n".join(out) + "\n"


if FORMAT == "json":
    print(json.dumps({"checked": stamp, "fixtures": bool(FIXTURES), "summary": summary,
                      "rows": rows}, indent=2))
else:
    print(table())
if MARKDOWN:
    with open(MARKDOWN, "w", encoding="utf-8", newline="\n") as f:
        f.write(markdown())
    if FORMAT != "json":
        print("Wrote " + MARKDOWN)
PY
