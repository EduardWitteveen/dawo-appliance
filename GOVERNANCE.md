# Governance

Hoe de DAWO appliance beheerd wordt: wie welke rol heeft, hoe wijzigingen binnenkomen en hoe besluiten vallen. De opbouw volgt de afspraken van het [OpenWebconcept](https://github.com/OpenWebconcept/.github) (OWC), net als [D-OmniTwin](https://github.com/TLaan/D-OmniTwin/blob/main/GOVERNANCE.md).

> **Concept (issue [#186](https://github.com/EduardWitteveen/dawo-appliance/issues/186)).** De appliance is een experimentele, onofficiële demonstrator. Punten die nog besloten moeten worden, staan onder *Nog open*.

Zie ook: [SUPPORT.md](./SUPPORT.md) (onderhoud en ondersteuning), [PARTICIPANTS.md](./PARTICIPANTS.md) (deelnemers), [CONTRIBUTING.md](./CONTRIBUTING.md) (werkwijze), [SECURITY.md](./SECURITY.md) (beveiligingsmeldingen) en de [gedragscode](./CODE_OF_CONDUCT.md).

## Uitgangspunten

- **Open source:** licentie EUPL-1.2 ([LICENSE](./LICENSE)).
- **Geen officiële distributie:** de appliance combineert openbare onderdelen van DAWO en Mijn Bureau, elk op een vaste versie. Het is geen product van DAWO, Mijn Bureau of het Ministerie van BZK, en mag niet zo gepresenteerd worden.
- **Upstream blijft upstream:** we gebruiken DAWO-Core en mijn-bureau-infra op een vastgelegde versie en kopiëren of forken ze niet zonder reden. Afwijkingen staan met motivatie in [`docs/deviations.md`](./docs/deviations.md).
- **Alles vastgelegd:** versies van alle onderdelen staan in [`manifest/appliance-manifest.json`](./manifest/appliance-manifest.json) en `flake.lock`; geen zwevende versies.
- **Geen afhankelijkheid van closed source**, tenzij in de README vermeld.
- **Pragmatisch:** alleen formeel waar het nodig is.

## Rollen

| Rol | Wie | Wat dat inhoudt |
| --- | --- | --- |
| **Eigenaar** | Nu: de maintainer (persoonlijke repository). Beoogd na overdracht: Gemeente Súdwest-Fryslân (*nog open*) | Houder van de repository; staat er garant voor (`legal` in [publiccode.yml](./publiccode.yml)). |
| **Beheerder** | Nu: de maintainer | Beoordeelt en merget pull requests, beheert releases en beveiligingsmeldingen, houdt de [roadmap](./docs/roadmap.md) bij en ondersteunt andere partijen, ook als die elkaars concurrent zijn. |
| **Deelnemer** | Zie [PARTICIPANTS.md](./PARTICIPANTS.md) | Gebruikt of test de appliance en levert wensen en feedback. |
| **Bijdrager** | Iedereen: gemeenten, andere overheden, leveranciers, inwoners | Meldt issues en levert pull requests volgens [CONTRIBUTING.md](./CONTRIBUTING.md). |
| **AI-assistenten** | Claude en Gemini, in opdracht van de beheerder | Werken volgens [AGENTS.md](./AGENTS.md) en [ADR 0005](./docs/adr/0005-ai-agent-conduct.md); de beheerder blijft verantwoordelijk. |

## Werkwijze

- **GitHub is de enige plek** voor issues, besluiten en voortgang ([ADR 0005](./docs/adr/0005-ai-agent-conduct.md)).
- **Elke wijziging via een pull request** naar `main`, vanuit een issue (GitHub Flow, zie [CONTRIBUTING.md](./CONTRIBUTING.md)).
- **Review:** een pull request wordt bij voorkeur goedgekeurd door een andere partij dan de indiener, liefst van een andere organisatie. Wijzigingen die het opstarten raken, gaan pas naar `main` na een groene KVM-test (zie [AGENTS.md](./AGENTS.md), *KVM merge gate*).
- **Branch protection** op `main` (pull request verplicht, controles groen, minimaal één goedkeuring) staat nog open: zie *Nog open*.
- **Beveiliging:** meldingen lopen privé via [SECURITY.md](./SECURITY.md), niet via openbare issues.
- **Upstream-fouten** blijven in deze repository (label `upstream`, en de tabel *Known upstream issues* in [`docs/deviations.md`](./docs/deviations.md)).

## Techniek

- Versies volgens [Semantic Versioning](https://semver.org/lang/nl/), één bron: `appliance.version` in het manifest. Bij elke versie een tag, een GitHub-release en een regel in de [CHANGELOG](./CHANGELOG.md). Zie [`docs/releasing.md`](./docs/releasing.md).
- Controles draaien bij elke pull request ([`.github/workflows/ci.yml`](./.github/workflows/ci.yml)); de opstarttests met KVM draaien lokaal ([`docs/testing.md`](./docs/testing.md)).

## Documentatie

- Documentatie staat bij de code, in deze repository; [`docs/README.md`](./docs/README.md) is de index.
- Technische documentatie is Engels. Documentatie voor gemeenten, beleidsadviseurs en eindgebruikers is Nederlands ([AGENTS.md](./AGENTS.md), regel 2). Dit document, [SUPPORT.md](./SUPPORT.md) en [PARTICIPANTS.md](./PARTICIPANTS.md) zijn Nederlands met een Engelse samenvatting.

## Besluitvorming

- **Code en documentatie:** in issues en pull requests, met review zoals hierboven.
- **Architectuur en scope:** in een ADR in [`docs/adr/`](./docs/adr/), na akkoord van de beheerder.
- **Governance zelf:** een wijziging van dit document gaat via een pull request met akkoord van de eigenaar.

## Nog open

Zie [#186](https://github.com/EduardWitteveen/dawo-appliance/issues/186):

1. Eigenaar en beheerder na de overdracht naar de organisatie van Súdwest-Fryslân.
2. Deelnemende organisaties.
3. Onderhoudstermijn tot en na de overdracht.
4. Branch protection: nu of bij de overdracht, en hoe de AI-assistenten dan mergen.
5. Contactadres voor beveiligingsmeldingen.

---

## English summary

The DAWO appliance follows the governance of the [OpenWebconcept](https://github.com/OpenWebconcept/.github), like D-OmniTwin. **Draft** (#186): today the maintainer owns and maintains the personal repository; the intended owner after the handover is the Municipality of Súdwest-Fryslân (open). Every change goes through a pull request from an issue, reviewed preferably by another party; changes that affect booting need a green KVM run. Versions follow SemVer with a tag, a GitHub release and a CHANGELOG entry. Security reports are private (SECURITY.md). Technical documentation is English; documentation for municipalities is Dutch. Open points: owner after handover, participants, maintenance term, branch protection, security contact.
