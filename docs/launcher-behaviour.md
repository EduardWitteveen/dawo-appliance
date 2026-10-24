# Launcher: what the page lets you do (behaviour)

The rules of the Launcher page (`launch/launcher.html`), written down before
they are programmed (the maintainer, 24 October; #284). One environment runs
at a time (ADR 0008), and either a person or the round (rondgang) is in
charge, never both. Texts on the page are Dutch; this description is English.

The page is always in exactly one of three situations. There are no states in
between: the moment a button is pressed, the page is in the situation that
button leads to.

## Situations

| Situation | When |
|---|---|
| **Idle** | Every environment is stopped and the round is off. |
| **Environment X active** | From the moment Starten is pressed on X: X starts, waits for its notice, is ready, or failed. The round is off. |
| **Round** | From the moment Rondgang nu starten is pressed until the round is stopped, wherever it is (at an environment, or between two). |

"Active" is X from the moment its Starten is pressed (before the server has
answered); after that, the first environment (in catalogue order) that is not
stopped or waits for its notice.

## Grey means inert

A grey card or box shows what it is (title, version, summary, its licence
line, its state) and **nothing can be done with it**: no buttons, no line
explaining why, nothing to open (the licence list and "Ook in deze omgeving"
do not unfold), no links. Grey itself says that something else is in charge.

## Per situation

### Idle

| Part | Looks | Buttons | Line |
|---|---|---|---|
| Every card | normal | Starten | (the card's problems, if any) |
| Round box | normal | Rondgang nu starten, the restart setting | — |

### Environment X active

| Part | Looks | Buttons | Line |
|---|---|---|---|
| Card X, starting | normal | Stoppen | the progress |
| Card X, being stopped | normal | — | "Wordt gestopt…" |
| Card X, waits for its notice | normal | Nu starten, Niet starten | the notice |
| Card X, ready | normal | **Openen**, Stoppen | the login, "Ook in deze omgeving" |
| Card X, failed | normal | Opnieuw proberen, Stoppen | the error in words; a link "Openen wat wel werkt" when it answers |
| Every other card | grey, inert | — | — |
| Round box | grey, inert | — | — |

### Round

| Part | Looks | Buttons | Line |
|---|---|---|---|
| Round box | normal | **Rondgang stoppen**, the restart setting | what it does now, and next |
| Card X (where the round is), starting | normal | — | the progress; "Gestart door de rondgang." |
| Card X, ready | normal | **Openen** | the login; "Gestart door de rondgang." |
| Every other card | grey, inert | — | — |

Stopping the round is the only way out while it runs: no card stops its
environment then, and Rondgang stoppen stops the environment the round is at
too, so the page is back to Idle. Openen is not a control (it opens a tab), so it stays on
the environment that is ready.

## Progress

- Steps are named for what they do for the person starting: the first step
  of a start on the laptop (it checks Docker and K3s and stops anything else,
  which mostly is nothing) is "Voorbereiden", not "Andere omgevingen even
  stilzetten".
- What goes wrong is said in words for the people who use it, never as a
  program's error ("TypeError: NetworkError …"). When the page cannot reach
  the Launcher for a moment (it is busy starting something), it waits and
  tries again quietly; only after half a minute without an answer it says
  "De Launcher reageert even niet; we proberen het opnieuw."

## Always

- While a start or stop is being sent, the button that was pressed waits
  (disabled) until it is done; the situation has changed already.
- Should two environments run at once anyway (not by the page; for example
  after a crash), the first is the active one; the other card is grey but
  keeps its **Stoppen**, the one exception to "grey is inert", so it can be
  put right.

## Checked by

- `tests/test-launcher-active.sh`: the rules above, on the page's own script.
- Haal Centraal (launch/haalcentraal: a small environment that starts in seconds; for the test it can
  fail at a step) with a browser test that clicks through every
  situation of this page, in `scripts/launcher-preview.sh`.
- The Launcher check in `nix/launch.nix`: the server side (one action at a time).
