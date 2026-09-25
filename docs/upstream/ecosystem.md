# The DAWO / Mijn Bureau ecosystem (as inspected on 2026-09-25)

Background for contributors: which upstream repositories exist, what they are
for, and which ones this appliance consumes. Facts below were checked on the
date above; revisions we actually pin are in `revisions.md` and
`manifest/appliance-manifest.json`.

> This appliance is an independent, unofficial experiment. Nothing here implies
> endorsement by, or affiliation with, the projects listed.

## Repositories

| Repository | What | Relation to this appliance |
| --- | --- | --- |
| **DAWO-Core** — <https://codeberg.org/DAWO/DAWO-Core> (primary since 0.1.2, 2026-08-14) | The workplace: NixOS flake with profiles, desktops (KDE Plasma 6, GNOME), hardening register, app sets, installer hosts. Formerly `MinBZK/DAWO-NixOS`. Releases 0.1.0 (2026-06-29), 0.1.1, 0.1.2, 0.1.3 (2026-09-07). GPL-3.0. | **Consumed** (pinned flake input, Slice 3). Backup mirrors: <https://code.overheid.nl/MinBZK/DAWO-NixOS>, <https://github.com/DAWO-community/DAWO-Core>. |
| **mijn-bureau-infra** — <https://code.overheid.nl/MinBZK/mijn-bureau-infra> (mirror: <https://github.com/MinBZK/mijn-bureau-infra>) | The collaboration suite deployment: Helmfile, per-app charts and values, single-VPS K3s scripts, docs at <https://minbzk.github.io/mijn-bureau-infra/>. EUPL-1.2. | **Consumed** (pinned revision, Slice 6). |
| `MinBZK/DAWO` — <https://code.overheid.nl/MinBZK/DAWO> | Umbrella repository of the DAWO initiative (components, including `componenten/samenwerksoftware`). | Reference only. |
| `MinBZK/DAWO-NixOS-installatie` | Dutch runbooks + scripts for USB/PXE imaging with `nixos-anywhere`, a provisioning station and a "Zaanstad-grade" overlay. | Not used; see `docs/adr/0002-own-installer-iso.md`. |
| **DAWO-Sextant** — <https://codeberg.org/DAWO/DAWO-Sextant> (also `MinBZK/DAWO-Sextant`) | Declarative fleet control plane for NixOS (proof of concept, Go): imaging station, device groups, change requests. The "GUI for NixOS management" mentioned in the press. | Out of scope (fleet management). |
| `MinBZK/DAWO-Rijk`, `DAWO-DWR`, `DAWO-IAM`, `DAWO-Mobile`, `DAWO-Cloud`, `DAWO-AI`, `DAWO-Fedora-Kinoite` | Sibling efforts (central-government variant, "Digitale Werkomgeving Reloaded", identity, mobile, cloud, AI, a Fedora Kinoite track). Mostly early or empty on the inspection date. | Reference only. |
| `MinBZK/bureaublad` | The Mijn Bureau dashboard app (`bureaublad`), the URL the appliance opens at the end. Consumed indirectly through mijn-bureau-infra image pins. | Indirect. |
| `MinBZK/mijn-bureau` — <https://github.com/MinBZK/mijn-bureau> | Research/communication repository for Mijn Bureau. | Reference only. |
| Community site — <https://dawo.community> | DAWO community entry point. | Reference only. |

## Context from public reporting (September 2026)

Summarised from Tweakers, "Nederland maakt soeverein alternatief voor Windows
en Office op basis van Linux" (Jasper Bakker, 2026-09-24), and linked sources:

- DAWO (Digitaal Autonome Werkomgeving Overheid) is a Ministry of the Interior
  (BZK) initiative. Its core team is named as Victor Gevers, Rutger Putter and
  Bram Buijs; the wider community contributes.
- In July 2026 the ICBR (interdepartmental committee for government operations)
  formally commissioned a standardised, more sovereign digital workplace; the
  three central-government IT providers SSC-ICT, DICTU and DUO-ICT execute it
  (see <https://www.dictu.nl/dictu-ssc-ict-en-duo-ict-samen-aan-de-slag-voor-een-soevereine-digitale-werkomgeving>).
- Eight municipalities take part in a VNG practical exploration; pilots run on
  written-off laptops. Earlier named participants include 's-Hertogenbosch,
  Zaanstad, Ede and Amsterdam; Groningen is investigating.
- The distribution moved from openSUSE via Fedora to NixOS. There is no formal
  timeline; a 1.0 is hoped for in 2027, decided by the community.
- Mijn Bureau is the collaboration suite track (Nextcloud + Collabora,
  Element/Synapse, Meet, Docs, Grist, Keycloak, the `bureaublad` dashboard),
  developed with municipalities, provinces and ministries and inspired by
  Germany's openDesk and France's La Suite.

Why this matters for the appliance: it confirms the two building blocks we
combine are the ones being piloted, and that the workplace's user experience
(ADR 0003) is what evaluators will compare against.
