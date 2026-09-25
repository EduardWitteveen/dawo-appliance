# Screenshot provenance

Written by `bash scripts/screenshots.sh`; do not edit or replace the images
by hand. Every image below was captured by a NixOS VM test of the pinned
configuration — see `docs/testing.md`.

- Date: 2026-09-25T12:17Z
- Repository: `e9714b3` (working tree had uncommitted changes)
- Pins: nixpkgs `fcb8fcd6bf2d`, DAWO-Core `0.1.3` (all: `manifest/appliance-manifest.json`)

| Image | Source test | What it shows |
| --- | --- | --- |
| `installer-plan.png` | `test-installer-boot` | The live ISO's console after `dawo-appliance-bootstrap plan`: pinned versions, the twelve steps, no disk writes. |
| `appliance-desktop.png` | `test-appliance-boot` | The installed host after auto-login: DAWO workplace (KDE Plasma 6) with the welcome dialog. Software-rendered in the test VM, so colours/fonts are as on a machine without GPU acceleration. |
