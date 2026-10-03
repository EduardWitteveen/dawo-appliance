# Changelog

All notable changes to the DAWO appliance. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/) (`appliance.version` in `manifest/appliance-manifest.json`; procedure in [`docs/releasing.md`](./docs/releasing.md)).

## [Unreleased] — towards 0.1.0

First version. Release checklist: [#175](https://github.com/EduardWitteveen/dawo-appliance/issues/175).

### Added
- **Live USB** (ADR 0006): boots an existing laptop from a USB SSD without touching its disk; DAWO workplace (Plasma) in about 20 s, Ubuntu 24.04 guest with single-node K3s in about a minute; data and debug logs on the `DAWO_LOGS` partition.
- **Mijn Bureau, laptop profile** (ADR 0007): Keycloak, Bureaublad, Nextcloud, Collabora and Element/Synapse deploy themselves in 14 phases (about 8 minutes once the images are on the stick); a status page shows progress and opens Mijn Bureau.
- Demo account `dawo`/`dawo` (D34), signed in automatically on the live USB (#173, D36).
- Per-install appliance CA and local DNS under `dawo.internal` (ADR 0004).
- Windows tool `scripts/windows/dawo-stick.ps1` to write the image while keeping `DAWO_LOGS`.
- Version and commit in the boot menu and the status page footer; release candidates `X.Y.Z-rc.N` (#175).
- Real-hardware screenshots (Dell Latitude 5550) and Dutch documentation for the target audience: demo script, apps tour, functional architecture.

### Fixed
- Guest collapse after about 48 minutes on CET-capable CPUs: the guest runs with `nousershstk` (#176, D35). Merged on a short Dell run; a run of more than an hour is still to confirm it.
- The status page says "klaar" only once the apps answer (#177).
- Dutch Firefox, sign-in pages and Nextcloud defaults on the live USB (#180, D37).

### Known issues
- `test-live-iso-boot` does not boot the guest in nested KVM under WSL (#184).
- Element asks to verify the device after each boot (#182).
- The stick tool's verify reports a false difference in the EFI partition (#165).
