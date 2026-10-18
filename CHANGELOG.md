# Changelog

All notable changes to the DAWO appliance. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/) (`appliance.version` in `manifest/appliance-manifest.json`; procedure in [`docs/releasing.md`](./docs/releasing.md)). `scripts/release.sh prepare X.Y.Z` turns the `[Unreleased]` section into `[X.Y.Z]`; its text becomes the GitHub release notes.

## [Unreleased]

## [0.1.0-rc.1] - 2026-10-18

First version, as a release candidate for testing on real hardware. Release checklist: [#175](https://github.com/EduardWitteveen/dawo-appliance/issues/175). The release is the live disk image `dawo-appliance-live.img`, downloaded from SourceForge (larger than GitHub's 2 GiB asset limit) and written with Rufus or balenaEtcher.

### Added
- **Live USB** (ADR 0006): boots an existing laptop from a USB SSD without touching its disk; DAWO workplace (Plasma) in about 20 s, Ubuntu 24.04 guest with single-node K3s in about a minute; data and debug logs on the `DAWO_LOGS` partition.
- **Disk image** `dawo-appliance-live.img` for Rufus, balenaEtcher or `dd`: the first boot grows its empty `DAWO_LOGS` to the end of the USB disk, so one USB SSD holds both the system and the data (#192, D39).
- **Four environments in the Launcher** (ADR 0008), each from the supplier's own demo setup with one override file, downloaded when started, one at a time: **Mijn Bureau**; **Valtimo** with Open Zaak, Objecten, Open Notificaties and Open Formulieren's citizen form (#246, #260); **Nextcloud Common Ground** with Conduction's apps, set up out of the box with demo data (#250, #259); **Tezza**, document base only, with a red notice before the download that its license is unclear (#261, #262). One generic runner for the compose environments (`appliance.composeEnvironments`).
- **One demo login** `launcher` / `launcher` in every environment and the components underneath (#258, D47); the workplace itself keeps its desktop user `dawo`.
- **The round** (#251): one minute after login the Launcher starts every environment in turn, 5 minutes each, round after round, and writes a report to `DAWO_LOGS`, as an unattended regression run on real hardware.
- **Launcher** (ADR 0008): the workplace boots clean and the Launcher opens at login with a card per environment (#229). The round starts **automatically one minute after login**, cancellable (#238, #257), and the Launcher shows a progress bar for the whole start and one for the current step (#232), the time left, the expected finish time and the current activity, in one browser tab, until *Klaar* (#235).
- **`launch` command line** (ADR 0008): `launch <id>` starts an environment through systemd, `launch --stop` stops it, `launch --status` shows which environments answer and where (#215, #228); preflight warnings before a start when the laptop falls short, the user may go ahead (#212). Environment catalogue under `environments/` (#203).
- **Mijn Bureau, laptop profile** (ADR 0007): Keycloak, Bureaublad, Nextcloud, Collabora and Element/Synapse deploy themselves in 14 phases (about 8 minutes once the images are on the stick).
- Demo account `launcher`/`launcher` for Mijn Bureau (D34), signed in automatically on the live USB (#173, D36).
- A notice before an environment starts (its terms, in red when the license is unclear), links on the card to what runs next to an environment with their logins, and the `launch` command line in the README (#252, #260, #261).
- Per-install appliance CA and local DNS under `dawo.internal` (ADR 0004).
- Windows tool `scripts/windows/dawo-stick.ps1` to write the image while keeping `DAWO_LOGS`.
- Version and commit in the boot menu and the status page footer; release candidates `X.Y.Z-rc.N` (#175).
- Nextcloud app Thematiq (NL Design System theming) installed by default; OpenRegister, Dossiq, Pipelinq and Portaliq pinned and installable later with `dawo-appliance-nc-app <id>` (#190, D38).
- Release script for the live disk image: `scripts/release.sh` plans by default, builds, stages with `SHA256SUMS`, prints the SourceForge upload command and creates a draft GitHub release (#175).
- Real-hardware screenshots (Dell Latitude 5550) and Dutch documentation for the target audience: demo script, apps tour, functional architecture.

### Changed
- DAWO-Core v0.2.0; nixpkgs kept at the earlier pin (#195, D40).
- A release no longer ships the installer ISO: the live disk image is the release artefact (ADR 0006); the installer ISO can still be built with `nix build .#installer-iso`.

### Fixed
- Mijn Bureau: the seven Nextcloud apps that upstream installs unpinned from the app store (including Nextcloud Office and `user_oidc` for single sign-on) are repaired with pinned releases when the store download failed (#205, U5); `user_oidc` pinned at 8.11.0, as 8.9.0 broke the first sign-in on Nextcloud 34 (#234).
- Mijn Bureaublad in Dutch (#225, U7); no translate pop-up over English pages (#222).
- Flatpak installs wait until Flathub answers, instead of failing at every boot before Wi-Fi is up (#218, U6).
- The guest is reset when its boot hangs in the firmware or GRUB for 3 minutes (#184), also after Mijn Bureau's one-time guest reboot.
- The Launcher: one start or stop at a time (a start queued behind a stop cancelled it), cards judged by their own units, a Stop on the card the round is at moves the round on (#257).
- `/etc/dawo-appliance/config` in the image is the cleaned flake source, never `.git` (#248).
- Log files on the stick are written atomically, and the final copy runs before the stick is unmounted (#197, #211).
- The stick tool verifies before Windows can touch the EFI partition, so no false difference any more (#165); a clear message for a disk number that does not exist (#220).
- Guest collapse after about 48 minutes on CET-capable CPUs: the guest runs with `nousershstk` (#176, D35).
- The status page says "klaar" only once the apps answer (#177); the Launcher is not ready while the environment still reports progress (#238).
- Dutch Firefox, sign-in pages and Nextcloud defaults on the live USB (#180, D37).
- `DAWO_LOGS` on the boot stick could stay unused at random ("cannot mount", data in RAM): the ISO was sometimes mounted from the whole USB disk instead of its partition (#192).

### Known issues
- `test-live-iso-boot` does not boot the guest in nested KVM under WSL (#184).
- Element asks to verify the device after each boot (#182).
- Valtimo: a submitted citizen form lands in Objecten and Open Zaak, not yet as a case in Valtimo (#260).
- Tezza: only the document base runs; its case-handling menus need the ZGW part, which does not fit in memory next to the workplace (#261). Its license is unclear (#262).
