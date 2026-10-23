#!/usr/bin/env bash
#
# Offline test for the launcher's step time and estimate (#235, #279): within
# last time's duration it gives an estimate; once a step takes longer than
# last time, no frozen "nog ongeveer ..." and no claim that it still runs.
# Runs the code between "BEGIN progress texts" and "END progress texts" in
# launch/launcher.html in Node. Skips without Node.
#
# SPDX-License-Identifier: EUPL-1.2
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if ! command -v node >/dev/null 2>&1; then echo "test-launcher-progress: SKIP (no node)"; exit 0; fi

node - <<'EOF'
const fs = require("fs");
const html = fs.readFileSync("launch/launcher.html", "utf8");
const m = html.match(/\/\/ BEGIN progress texts\n([\s\S]*?)\/\/ END progress texts/);
let pass = 0, fail = 0;
const ok = (c, msg) => { if (c) { pass++; console.log("  PASS " + msg); } else { fail++; console.log("  FAIL " + msg); } };
if (!m) { console.log("  FAIL no BEGIN/END progress texts markers"); process.exit(1); }
const dur = s => `${Math.round(s)}s`, clock = t => `@${Math.round(t)}`;
const progressTexts = new Function("dur", "clock", m[1] + "\nreturn progressTexts;")(dur, clock);

let r = progressTexts(60, 300, "120", 1000);
ok(r.eta === "nog ongeveer 360s · klaar rond @1360", `on time: an estimate (got '${r.eta}')`);
r = progressTexts(2940, 446, "133", 1000);  // the Dell, 23 October: 49 min on a 7 min step
ok(!/nog ongeveer/.test(r.eta || ""), `overrun: no 'nog ongeveer' (got '${r.eta}')`);
ok(/langer dan vorige keer/.test(r.eta || ""), "overrun: says it takes longer than last time");
ok(!/loopt nog/.test(r.time), `overrun: does not claim it still runs (got '${r.time}')`);
r = progressTexts(60, 0, "120", 1000);
ok(r.eta === null && r.time === "60s bezig", "no previous time: no estimate");
r = progressTexts(60, 300, "", 1000);
ok(r.eta === null, "unknown later steps: no estimate");
console.log(`\ntest-launcher-progress: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
EOF
