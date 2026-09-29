# Real-hardware screenshots

Written by `bash scripts/screenshots.sh --stick ...`; do not edit or replace
the images by hand. Each image is a debug-mode screenshot that the live USB
saved on its `DAWO_LOGS` stick while running on one of the maintainer's own
test laptops (`docs/live-usb.md`), cropped to its centre and scaled down,
nothing else. Rules: [`README.md`](README.md).

| Image | Machine | Session (UTC boot time_boot id) | Captured (local time) | Original SHA-256 | What it shows |
| --- | --- | --- | --- | --- | --- |
| `live-status-page-dell.png` | Dell Inc. Latitude 5550 | `20260929T201150Z_ea1e1aaa` | 2026-09-29 22:22:42 | `00011333445bcdfe…` | The live USB on a Dell Latitude 5550 (USB SSD): the status page at step 11 of 14 (in-cluster trust) with the typical duration, the time since the last activity and the latest log line; steps 1-10 passed. |
| `live-status-deploying.png` | Dell Inc. Latitude 5550 | `20260929T144234Z_5f4f1f4d` | 2026-09-29 16:47:23 | `fb4c048c2a5e7bff…` | An earlier session on the same laptop while Mijn Bureau installs its apps (step 8 of 14): spinner, time since the last activity, latest log line. |
