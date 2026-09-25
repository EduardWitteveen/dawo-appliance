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
- Later: the Ubuntu/K3s guest coming up, the health check, the Mijn Bureau
  dashboard in the browser (Slices 4–7).

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
(`.gitattributes`). Keep the set small (a few hundred KB total).

## When

Refresh on every slice completion and every upstream pin bump, after
`scripts/verify.sh` is green and before the README is updated, so text,
pictures and pins agree. The README caption names the DAWO-Core tag shown.
