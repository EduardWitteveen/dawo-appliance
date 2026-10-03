# Security

The DAWO appliance is an **experimental demonstrator, not for production and not for real data**. By design its demo passwords are public, the USB disk is not encrypted and debug mode stores screenshots on the stick (see [`docs/live-usb.md`](./docs/live-usb.md) and the [functional architecture](./docs/audience/functionele-architectuur.md)). Those are known properties, not vulnerabilities.

## Reporting a vulnerability

Report anything else that could harm users (for example a way to reach the appliance from the network, a secret in the repository, or a supply-chain problem in a pinned component) **privately**, not in a public issue:

- GitHub: **Security → Report a vulnerability** on this repository (private vulnerability reporting; draft, to be enabled, #186).

Please include what you found, how to reproduce it and which version (boot menu or status page footer). The maintainer acknowledges a report as soon as possible and agrees a disclosure date with you. Problems in upstream components (DAWO-Core, Mijn Bureau, NixOS, Ubuntu, the apps) are passed on to their maintainers.

## Supported versions

Only the latest release. Until the first release, only `main`.

---

## Nederlands, kort

De appliance is een experimentele demonstrator, niet voor productie of echte gegevens. Openbare demowachtwoorden, geen schijfversleuteling en screenshots in de debug-modus zijn bekende eigenschappen. Andere beveiligingsproblemen meld je **privé** via *Security → Report a vulnerability* op GitHub, niet in een openbaar issue.
