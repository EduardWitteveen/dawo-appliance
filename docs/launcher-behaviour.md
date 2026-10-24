# Launcher: what the page lets you do (behaviour)

The rules of the Launcher page (`launch/launcher.html`), written down before
they are programmed (the maintainer, 24 October; #284). One environment runs
at a time (ADR 0008), and either a person or the round (rondgang) is in
charge, never both. Texts on the page are Dutch; this description is English.

## Situations

| Situation | When |
|---|---|
| **Idle** | Every environment is stopped and the round is off. |
| **Environment X active** | X is starting, waits for its notice, is ready, or failed; the round is off. |
| **Round** | The round is on. It may be at an environment X (starting or ready), or between two. |

"Active" is decided by the page from the states it gets: the first
environment (in catalogue order) that is not stopped or waits for its notice.

## Per situation

### Idle

| Part | Looks | Buttons | Line |
|---|---|---|---|
| Every card | normal | Starten | (the card's problems, if any) |
| Round box | normal | Rondgang nu starten | — |

### Environment X active

| Part | Looks | Buttons | Line |
|---|---|---|---|
| Card X, starting | normal | Stoppen | the progress |
| Card X, waits for its notice | normal | Nu starten, Niet starten | the notice |
| Card X, ready | normal | **Openen**, Stoppen | the login, "Ook in deze omgeving" |
| Card X, failed | normal | Opnieuw proberen, Stoppen | the error; a link "Openen wat wel werkt" when it answers |
| Every other card | grey | Starten, disabled | "Er draait al een omgeving: stop eerst X." |
| Round box | grey | Rondgang nu starten, disabled | "Er draait al een omgeving: stop eerst X." |

### Round

| Part | Looks | Buttons | Line |
|---|---|---|---|
| Round box | normal | **Rondgang stoppen** | what it does now, and next |
| Card X (where the round is), starting | normal | — | "Gestart door de rondgang; stoppen gaat met 'Rondgang stoppen'." |
| Card X, ready | normal | **Openen** | the same line |
| Every other card | grey | — | "De rondgang loopt: stop eerst de rondgang." |

Stopping the round is the only way out while it runs: no card stops its
environment then. Openen is not a control (it opens a tab), so it stays.

## Always

- While a start or stop is being sent, every Starten/Stoppen button waits
  (disabled) until it is done.
- Should two environments run at once anyway (not by the page; for example
  after a crash), the first is the active one; the other card is grey but
  keeps its **Stoppen**, so it can be put right.
- The round's setting "Na herstart meteen verder" is a setting, not a start:
  it can be switched in every situation.

## Checked by

`tests/test-launcher-active.sh` (the rules above, on the page's code) and the
Launcher check in `nix/launch.nix` (the server side: one action at a time).
