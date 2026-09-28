# Real-hardware screenshots

Written by `bash scripts/screenshots.sh --stick ...`; do not edit or replace
the images by hand. Each image is a debug-mode screenshot that the live USB
saved on its `DAWO_LOGS` stick while running on one of the maintainer's own
test laptops (`docs/live-usb.md`), cropped to its centre and scaled down,
nothing else. Rules: [`README.md`](README.md).

| Image | Machine | Session (UTC boot time_boot id) | Captured (local time) | Original SHA-256 | What it shows |
| --- | --- | --- | --- | --- | --- |
| `live-status-page-dell.png` | Dell Inc. Latitude 5550 | `20260928T181335Z_f2a3b727` | 2026-09-28 20:18:20 | `3648a47073615ba4…` | The live USB on a Dell Latitude 5550: the status page while Mijn Bureau deploys at step 8 of 14 (helmfile apply), after steps 1-7 passed. |
