# The DAWO / Mijn Bureau ecosystem (as inspected on 2026-09-25; VNG webinar context 2026-09-30)

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

## Context from the VNG webinar (2026-09-30)

VNG webinar "Update Digitale Autonome Werkomgeving Overheid (DAWO): de samenhang
tussen NDS, ICBR en de gemeentelijke Uitvoeringsstrategie" (VNG / NDS
Aanjaagteam Cloud en autonome werkomgeving; recording:
<https://youtu.be/_76KUonxHis>; slides sent to participants, not stored here):

- **Why:** municipalities are the largest executive organisation in the
  Netherlands (342 municipalities, more than 200,000 workplaces); their digital
  workplace depends almost entirely on one supplier (Microsoft 365). The risks
  named: unilateral licence costs, confidentiality under US law (CLOUD Act,
  FISA 702), and continuity (outage, sanctions, a supplier decision). Guiding
  principle: public-sector digitalisation is organised independently.
- **DAWO is goal 3** of the municipal implementation strategy on cloud
  (VNG, track 2): interadministrative and European cooperation and a broad
  practical exploration of an autonomous workplace with municipalities.
- **The ecosystem as presented** (code.overheid.nl in the centre):
  - *Mijn Bureau* (building block, since January 2025): from BZK, EU
    cooperation in an EDIC, an open collaboration environment with La Suite,
    openDesk and Nextcloud; **in transition to SSC-ICT from Q3 2026**.
  - *SSC-ICT · DAWO* (since 2025): the open-source blueprint: NixOS workplace,
    IAM, cloud and management.
  - *VNG and municipalities* (since March 2026): the practical exploration
    (contact: digitalisering@vng.nl).
  - *DAWO community* (June 2026): broadening, and exploring a merger of DAWO
    and Mijn Bureau into one movement.
  - *Sextant* (summer 2026): fleet management for the workplace, from practice
    with the community (see DAWO-Sextant above).
  - *ICBR commission* (July 2026): SSC-ICT, DICTU and DUO-ICT build autonomous
    workplace services for central government; it funds the base.
  - *NDS steering group*: a government-wide vision on the autonomous workplace
    (in progress).
  - *NL Digitale Dienst* (intended, in time): direction and standards, the
    long-term home for codebase stewardship.
- **Agenda:** EU TechFest (27 October 2026), FieldLab Soevereine Basis
  (23–25 November 2026), OneGov Hackathon and suppliers' meeting (9–10 December
  2026).

What it means for the appliance: the combination we demonstrate (the DAWO
workplace plus Mijn Bureau on one machine) matches the announced merger of the
two tracks, and the practical exploration with municipalities is the audience
for the demo. Whether to show the appliance at one of the events above is the
maintainer's call. The pinned upstream locations stay as they are; when Mijn
Bureau moves to SSC-ICT, its repository location is checked again
(`scripts/check-upstream.sh`).

Why this matters for the appliance: it confirms the two building blocks we
combine are the ones being piloted, and that the workplace's user experience
(ADR 0003) is what evaluators will compare against.
