#!/usr/bin/env bash
#
# Behaviour test for the launcher page (#284): the situations of
# docs/launcher-behaviour.md (idle, one environment active, the round; grey
# is inert), run on
# the page's own script with a minimal DOM. Per card and for the round's box
# it checks what docs/launcher-behaviour.md says: grey or not, which buttons
# (and whether they are disabled), and the line. Skips without Node.
#
# SPDX-License-Identifier: EUPL-1.2
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if ! command -v node >/dev/null 2>&1; then echo "test-launcher-active: SKIP (no node)"; exit 0; fi

node - <<'EOF'
const fs = require("fs");
const html = fs.readFileSync("launch/launcher.html", "utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
let pass = 0, fail = 0;
const ok = (c, msg) => { if (c) { pass++; console.log("  PASS " + msg); } else { fail++; console.log("  FAIL " + msg); } };

// A minimal DOM: elements are plain objects; the page's own el() builds them.
const node = tag => ({ tag, className: "", attrs: {}, children: [], style: {}, dataset: {}, parent: null,
  append(...k) { for (const c of k) { if (typeof c === "object") c.parent = this; this.children.push(c); } },
  setAttribute(k, v) { this.attrs[k] = v; }, addEventListener() {},
  replaceChildren(...k) { this.children = []; this.append(...k); },
  // By tag name ("details", "a", "button"); the page's inert() uses them.
  querySelectorAll(sel) { const out = []; const f = n => (n.children || []).forEach(k => { if (typeof k === "object") { if (k.tag === sel) out.push(k); f(k); } }); f(this); return out; },
  remove() { if (this.parent) this.parent.children = this.parent.children.filter(c => c !== this); },
  replaceWith(x) { if (!this.parent) return; const i = this.parent.children.indexOf(this); this.parent.children.splice(i, 1, x); if (typeof x === "object") x.parent = this.parent; },
  get textContent() { const t = n => typeof n === "string" ? n : (n.children || []).map(t).join(""); return t(this); },
  set textContent(v) { this.children = [String(v)]; },
  // ".name": the first descendant with that class; an empty element otherwise (the page writes into it)
  querySelector(sel) { const c = sel.replace(/^\./, ""); const f = n => (n.children || []).reduce((hit, k) =>
    hit || (typeof k === "object" && (new RegExp(`\\b${c}\\b`).test(k.className || "") ? k : f(k))), null); return f(this) || node("div"); },
  getAttribute(k) { return this.attrs[k]; } });
const roots = { grid: node("div"), cycle: node("div") };
const document = { createElement: node, getElementById: id => roots[id] || node("div"), querySelectorAll: () => [], querySelector: () => null };
const page = new Function("document", "setInterval", "fetch", "location",
  script + "\nreturn { render, renderCycle, setRound: v => { ROUND_ACTIVE = v; }, setActing: v => { acting = v; } };")(
  document, () => 0, () => new Promise(() => {}), { reload() {} });

// What a card or the round's box shows.
const texts = n => typeof n === "string" ? n : (n.children || []).map(texts).join("");
const all = (n, f, out = []) => { if (n && typeof n === "object") { if (f(n)) out.push(n); (n.children || []).forEach(c => all(c, f, out)); } return out; };
const look = n => ({
  grey: /\bblocked\b/.test(n.className || n.attrs.class || ""),
  buttons: all(n, x => x.tag === "button" || (x.tag === "a" && /\bbutton\b/.test(x.className || x.attrs.class || "")))
    .map(b => texts(b) + ("disabled" in b.attrs ? " (disabled)" : "")),
  note: all(n, x => /blocked-note|round-note/.test(x.className || x.attrs.class || "")).map(texts).join(" "),
});
const env = (id, state, extra = {}) => ({ id, title: id.toUpperCase(), version: "", summary: "", url: "http://x/", problems: [], state, ...extra });
const cards = (data, round = false) => { page.setRound(round); page.render(data); return Object.fromEntries(data.map((e, i) => [e.id, look(roots.grid.children[i])])); };
const box = (cycle) => { page.renderCycle({ available: true, ...cycle }); return look(roots.cycle.children[0]); };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

console.log("-- idle --");
let c = cards([env("a", "stopped"), env("b", "stopped")]);
ok(!c.a.grey && same(c.a.buttons, ["Starten"]) && c.a.note === "", "every card: normal, Starten");
let r = box({ active: false });
ok(!r.grey && r.buttons.includes("Rondgang nu starten") && r.note === "", "round box: normal, Rondgang nu starten");

console.log("-- environment X active --");
for (const [state, want, extra] of [
  ["starting", ["Stoppen"], { progress: { step: 1, steps: 2, label: "x", started: 1, expected: 10 } }],
  ["ready", ["Openen", "Stoppen"], {}],
  ["failed", ["Opnieuw proberen", "Stoppen"], {}],
]) {
  c = cards([env("x", state, extra), env("o", "stopped")]);
  ok(!c.x.grey && same(c.x.buttons, want), `card X ${state}: normal, ${want.join(" + ")}`);
  ok(c.o.grey && same(c.o.buttons, []) && c.o.note === "", `${state}: other card grey and inert (no buttons, no line)`);
  r = box({ active: false });
  ok(r.grey && same(r.buttons, []) && r.note === "", `${state}: round box grey and inert`);
}
c = cards([env("x", "stopped", { pending: { at: 1 }, notice: { title: "t", text: "n" } }), env("o", "stopped")]);
ok(!c.x.grey && same(c.x.buttons, ["Nu starten", "Niet starten"]) && c.o.grey, "card X waits for its notice: Nu starten + Niet starten; other card grey");

console.log("-- round --");
r = box({ active: true, round: 1, phase: "up", env: "x" });
ok(!r.grey && r.buttons.includes("Rondgang stoppen"), "round box: normal, Rondgang stoppen");
c = cards([env("x", "starting", { progress: { step: 1, steps: 2, label: "x", started: 1, expected: 10 } }), env("o", "stopped")], true);
ok(!c.x.grey && same(c.x.buttons, []) && c.x.note === "Gestart door de rondgang.", "card X starting: normal, no buttons, says the round started it");
c = cards([env("x", "ready"), env("o", "stopped")], true);
ok(!c.x.grey && same(c.x.buttons, ["Openen"]), "card X ready: Openen only");
ok(c.o.grey && same(c.o.buttons, []) && c.o.note === "", "other card: grey and inert (no buttons, no line)");
c = cards([env("x", "stopped"), env("o", "stopped")], true);
ok(c.x.grey && c.o.grey && same(c.x.buttons, []), "between two environments: every card grey, no buttons");

console.log("-- always --");
page.setActing(true);
c = cards([env("x", "ready"), env("o", "stopped")]);
ok(same(c.x.buttons, ["Openen", "Stoppen (disabled)"]), "while an action is sent: Stoppen waits (Openen stays)");
page.setActing(false);
c = cards([env("x", "ready"), env("y", "ready")]);
ok(!c.x.grey && c.y.grey && c.y.buttons.includes("Stoppen"), "two running anyway: the first is active, the other grey but keeps Stoppen");

console.log(`\ntest-launcher-active: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
EOF
