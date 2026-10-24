#!/usr/bin/env bash
#
# Offline test for "one environment at a time" on the launcher page (#284):
# while one environment is not stopped (or waits for its notice), it is the
# active one and the other cards are greyed out and cannot be started.
# The round (#284 follow-up) too. Runs activeEnv() (between "BEGIN active environment" and "END active
# environment" in launch/launcher.html) in Node, and checks that card() uses
# it. Skips without Node.
#
# SPDX-License-Identifier: EUPL-1.2
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if ! command -v node >/dev/null 2>&1; then echo "test-launcher-active: SKIP (no node)"; exit 0; fi

node - <<'EOF'
const fs = require("fs");
const html = fs.readFileSync("launch/launcher.html", "utf8");
const m = html.match(/\/\/ BEGIN active environment\n([\s\S]*?)\/\/ END active environment/);
let pass = 0, fail = 0;
const ok = (c, msg) => { if (c) { pass++; console.log("  PASS " + msg); } else { fail++; console.log("  FAIL " + msg); } };
if (!m) { console.log("  FAIL no BEGIN/END active environment markers"); process.exit(1); }
const activeEnv = new Function(m[1] + "\nreturn activeEnv;")();
const env = (id, state, pending) => ({ id, state, ...(pending ? { pending: { at: 1 } } : {}) });

ok(activeEnv([env("a", "stopped"), env("b", "stopped")]) === null, "all stopped: none is active");
for (const st of ["starting", "ready", "failed"]) {
  ok((activeEnv([env("a", "stopped"), env("b", st)]) || {}).id === "b", `${st}: that one is active`);
}
ok((activeEnv([env("a", "stopped", true), env("b", "stopped")]) || {}).id === "a", "waiting for its notice: active");
ok(/const isActive = !!active && active\.id === env\.id/.test(html) && /const blocked = !!active \? !isActive : round/.test(html), "card() greys out every card but the active one (all while the round runs without one)");
ok(/acting \|\| blocked \? \{ disabled: "" \}/.test(html), "a blocked card's Starten is disabled");
ok(/stop eerst \$\{active\.title\}/.test(html), "a blocked card says which one to stop first");
// The round: while it runs only its own Stop works; while an environment runs it cannot start.
ok(/if \(round\) \{[^}]*env\.state === "ready"\) actions\.append\(el\("a"[^}]*"Openen"/.test(html), "while the round runs the active environment still opens when ready (Openen is no control)");
ok(!/if \(round\) \{[^}]*act\("(start|stop)"/.test(html), "while the round runs a card has no Starten or Stoppen");
ok(/De rondgang loopt: stop eerst de rondgang\./.test(html), "a card says the round has to be stopped first");
ok(/cycleAct\("start"\), \.\.\.\(ACTIVE_ENV \? \{ disabled: "" \} : \{\}\)/.test(html), "while an environment runs the round cannot be started");
ok(/if \(was !== ROUND_ACTIVE\) \{ lastJson = ""; refresh\(\); \}/.test(html) && /if \(changed && lastCycleData\) renderCycle\(lastCycleData\)/.test(html),
   "the cards and the round's box redraw each other when either changes");
console.log(`\ntest-launcher-active: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
EOF
