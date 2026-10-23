#!/usr/bin/env bash
#
# Offline test for the licence block on the launcher cards (#273), after the
# maintainer's review of 23 October: closed it is one short line without
# the colour's name, the reason is plain text inside, and the parts and the
# licences used are lists that open on their own.
# Runs the block's code (between "BEGIN licences" and "END licences" in
# launch/launcher.html) in Node with a minimal element stub. Skips without
# Node.
#
# SPDX-License-Identifier: EUPL-1.2
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if ! command -v node >/dev/null 2>&1; then echo "test-launcher-licences: SKIP (no node)"; exit 0; fi

node - <<'EOF'
const fs = require("fs");
const html = fs.readFileSync("launch/launcher.html", "utf8");
const m = html.match(/\/\/ BEGIN licences\n([\s\S]*?)\/\/ END licences/);
let pass = 0, fail = 0;
const ok = (c, msg) => { if (c) { pass++; console.log("  PASS " + msg); } else { fail++; console.log("  FAIL " + msg); } };
if (!m) { console.log("  FAIL no BEGIN/END licences markers"); process.exit(1); }
// A minimal element: tag, attributes, children.
const el = (tag, attrs, ...children) => ({ tag, attrs: attrs || {}, children: children.filter(c => c != null) });
const licencesBlock = new Function("el", m[1] + "\nreturn licencesBlock;")(el);
const text = n => typeof n === "string" ? n : n.children.map(text).join("");
const find = (n, f) => typeof n === "string" ? [] : [...(f(n) ? [n] : []), ...n.children.flatMap(c => find(c, f))];

const env = {
  licences: { level: "red", open: 1, total: 3, reason: "Niet open source (gesloten): X. Geen licentie gevonden: Y.",
              counts: { "Apache-2.0": 1, "LicenseRef-proprietary": 1, "NOASSERTION": 1 },
              classes: [{ name: "a", class: "open" }, { name: "x", class: "closed" }, { name: "y", class: "unknown" }] },
  components: [{ name: "a", repo: "https://example.invalid/a", license: "Apache-2.0" },
               { name: "x", repo: "https://example.invalid/x", license: "LicenseRef-proprietary" },
               { name: "y", repo: "https://example.invalid/y", license: "NOASSERTION" }],
};
const b = licencesBlock(env);
ok(b.tag === "details", "the block is closed by default (details)");
const sum = text(b.children[0]);
ok(sum === "Niet alles open source", `closed it says 'Niet alles open source' (got '${sum}')`);
ok(!/rood|geel|groen/i.test(text(b)), "it does not name the colour");
ok(text(b).includes("Geen licentie gevonden: Y"), "the reason is inside");
const subs = find(b, n => n !== b && n.tag === "details");
ok(subs.length === 2 && /^Onderdelen/.test(text(subs[0].children[0])) && /^Gebruikte licenties/.test(text(subs[1].children[0])),
   "the parts and the licences used are two lists that open on their own");
const items = find(subs[0], n => n.tag === "li").map(text);
ok(items[0].startsWith("x") && items[2].startsWith("a"), "closed parts first, open parts last");
for (const [level, want] of [["green", "Alles open source"], ["yellow", "Onduidelijke licenties"]]) {
  const t = text(licencesBlock({ ...env, licences: { ...env.licences, level } }).children[0]);
  ok(t === want, `${level}: '${want}' (got '${t}')`);
}
ok(licencesBlock({ licences: { total: 0 } }) === null, "no block without licence data");
console.log(`\ntest-launcher-licences: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
EOF
