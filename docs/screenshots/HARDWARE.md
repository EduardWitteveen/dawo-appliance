# Real-hardware screenshots

Written by `bash scripts/screenshots.sh --stick ...`; do not edit or replace
the images by hand. Each image is a debug-mode screenshot that the live USB
saved on its `DAWO_LOGS` stick while running on one of the maintainer's own
test laptops (`docs/live-usb.md`), cropped to its centre and scaled down,
nothing else. Rules: [`README.md`](README.md).

| Image | Machine | Session (UTC boot time_boot id) | Captured (local time) | Original SHA-256 | What it shows |
| --- | --- | --- | --- | --- | --- |
| `live-status-deploying.png` | Dell Inc. Latitude 5550 | `20260929T144234Z_5f4f1f4d` | 2026-09-29 16:47:23 | `fb4c048c2a5e7bff…` | An earlier session on the same laptop while Mijn Bureau installs its apps (step 8 of 14): spinner, time since the last activity, latest log line. |
| `live-status-page-dell.png` | Dell Inc. Latitude 5550 | `20260930T071508Z_59de7dac` | 2026-09-30 09:23:52 | `e2183babf5ad79aa…` | Status page after all 14 phases: Mijn Bureau ready, Open Mijn Bureau button, Dell Latitude 5550, USB SSD |
| `live-bureaublad-dell.png` | Dell Inc. Latitude 5550 | `20260930T111822Z_ec4e1ce7` | 2026-09-30 13:41:15 | `19abe4ca7ec234ae…` | Mijn Bureaublad dashboard after logging in as dawo/dawo, with Element and Nextcloud open in tabs (main ad68322) |
| `live-login-dell.png` | Dell Inc. Latitude 5550 | `20260930T111822Z_ec4e1ce7` | 2026-09-30 13:39:44 | `100dd8c4217d6282…` | Mijn Bureau sign-in page (Keycloak, realm mijnbureau) with the demo user dawo |
| `live-nextcloud-dell.png` | Dell Inc. Latitude 5550 | `20260930T111822Z_ec4e1ce7` | 2026-09-30 13:42:16 | `04db6f766b4b03ee…` | Nextcloud Files after single sign-on from Bureaublad (empty home, 10 GB quota) |
| `live-element-dell.png` | Dell Inc. Latitude 5550 | `20260930T111822Z_ec4e1ce7` | 2026-09-30 13:41:46 | `1a24f78259b559af…` | Element chat after single sign-on: Welcome DAWO Demo, room #welkom |
| `live-collabora-dell.png` | Dell Inc. Latitude 5550 | `20260930T185043Z_63d69852` | 2026-09-30 21:02:29 | `12e94bfc95ed2eda…` | Collabora Online editing Document.docx inside Nextcloud after automatic sign-in (branch test/iso-173-176-177) |
