# Screenshots

Pictures of the appliance for the README and for anyone deciding whether to
try it. This directory holds the images and their provenance
(`PROVENANCE.md`); the rules below say why they exist, what may go in, how
they are made and when they are refreshed.

## Why

A demo appliance is judged by what it looks like before anyone boots it. The
pictures answer "what will I get?" in one glance: the installer that writes
nothing until told, the DAWO workplace exactly as the pilots see it, and (from
Slice 7) Mijn Bureau in the browser.

## What

Only pictures of the **pinned configuration as it really behaves**:

- `installer-plan.png` — the live ISO after `dawo-appliance-bootstrap plan`.
- `appliance-desktop.png` — the installed host after auto-login, with the
  welcome dialog.
- `live-*.png` — the live USB on real hardware (#118): one debug screenshot
  per milestone from a session on one of the maintainer's own test laptops,
  e.g. `live-status-page-dell.png`. Provenance in `HARDWARE.md`.
- `live-launch-cli.png` — the `launch` command line (`launch`,
  `launch --check valtimo`, `launch --status`) in a terminal on the live
  image, from the KVM test `test-live-launch` (#252). Provenance in
  `TESTS.md`.
- Later: the Mijn Bureau dashboard in the browser.

Not allowed: mock-ups, retouched images, pictures of upstream's pilots or of
other people's machines, anything containing a real person's data, or
anything that could pass for official DAWO/Mijn Bureau/BZK material. The
"experimental, unofficial" banner in the welcome dialog stays visible.

## How

Every image is captured by a NixOS VM test (`test-installer-boot`,
`test-appliance-boot`) with `machine.screenshot(...)`, then copied here by
`bash scripts/screenshots.sh`, which also writes `PROVENANCE.md` (date, git
revision, pins). That makes each picture reproducible: same pins, same image.
Images are PNG, at the test VM's resolution, committed as binary
(`.gitattributes`). Keep the set small (about 2 MB total; replace a
real-hardware picture rather than adding one per session).

Real-hardware pictures come from the live USB's debug mode, which saves a
screenshot every 30 s on the `DAWO_LOGS` stick (`docs/live-usb.md`). After a
session, the logs are copied off the stick and
`bash scripts/screenshots.sh --stick <session-dir> <file.png> <dest.png> "<what>"`
takes one of them in: cropped to its centre and scaled to 1280 px wide,
nothing else, with the machine, session, capture time and the original's
SHA-256 in the generated `HARDWARE.md`. Pick a frame with no personal data on
screen; the demo password `dawo` is fine.

KVM-test pictures of the live image come the same way, without hardware:
`test-live-launch` boots the real live image with an emulated `DAWO_LOGS`
stick, its self-test opens a terminal with the `launch` commands and saves
`launch-cli.png` next to the 30-s debug screenshots, and the test copies them
off the stick image (`tests/exfat-read.py`, read-only) into
`result/screens/`. Then
`bash scripts/screenshots.sh --test <result-dir> <file.png> <dest.png> "<what>"`
takes one in, cropped and scaled as above, with the test, its result path,
the session, the git revision and the original's SHA-256 in the generated
`TESTS.md`. Run it from a normal checkout (in a git worktree under WSL the
revision reads `unknown`).

## When

Refresh on every slice completion and every upstream pin bump, after
`scripts/verify.sh` is green and before the README is updated, so text,
pictures and pins agree. The README caption names the DAWO-Core tag shown.

After every live-USB session on real hardware (#118): read the stick, update
the README's "Live" status row with what the session reached, and replace the
real-hardware picture when it shows new progress.
