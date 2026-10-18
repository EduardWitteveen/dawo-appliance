# Screenshots from KVM test runs

Written by `bash scripts/screenshots.sh --test ...`; do not edit or replace
the images by hand. Each image is a desktop screenshot that the real live
image saved on the emulated `DAWO_LOGS` stick of a KVM test run (debug mode,
`hosts/appliance/live-logs.nix`; `launch-cli.png` by the Launch self-test,
`hosts/appliance/live-launch-selftest.nix`), taken off the stick image by the
test with `tests/exfat-read.py`, cropped to its centre and scaled down,
nothing else. The test VM has no GPU (software rendering) and no internet.
Rules: [`README.md`](README.md).

| Image | Source test | Test result | Session (UTC boot time_boot id) | Repository | Original SHA-256 | What it shows |
| --- | --- | --- | --- | --- | --- | --- |
| `live-launch-cli.png` | `test-live-launch` | `q8a7wy73cwg9zk2ym1zxa138c99cp46k-live-launch` | `20261018T073309Z_c37bce65` | `unknown` | `a734fa7592e7c5ff…` | De opdracht launch: vier omgevingen, launch --check valtimo en launch --status |
