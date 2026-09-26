# Doel en Context (Purpose and rationale)

> Experimenteel en onofficieel. Dit is geen officiële distributie van DAWO, Mijn Bureau of BZK, en wordt niet door hen onderschreven. Zie `README.md`.

Dit document beschrijft wat de `dawo-appliance` precies is, waarom dit project bestaat naast de officiële landelijke projecten, waar we bewust afwijken van de standaard, en wat daarvan de voor- en nadelen zijn. Dit is het referentiekader voor discussies over de scope. Specifieke technische keuzes worden vastgelegd in architecturele besluiten (ADR's) in `docs/adr/`.

## In één alinea

De `dawo-appliance` smeedt twee losse open-source overheidsprojecten samen tot **één zelfstandige, reproduceerbare demonstratie-machine**: je start een kleine installatie-USB op een x86-64 laptop, bevestigt de harde schijf, en je eindigt met de **DAWO werkplek** (de veilige NixOS overheids-desktop, exact zoals in de pilots) op je scherm. Op de achtergrond draait een virtuele machine (KVM) met **Mijn Bureau** (de overheids-samenwerkingssuite) op een lokaal K3s Kubernetes cluster, waarna het Mijn Bureau dashboard direct opent in de browser. Elk softwarecomponent is muurvast gezet op een exacte versie (pinned) in één manifest.

## Het gat dat we vullen

De twee officiële projecten zijn uitstekend in wat ze doen, maar zijn niet gebouwd om samen als één demonstratie te draaien:

- **DAWO-Core** levert de werkplek (als NixOS configuratie) en installeert deze met 'fleet tooling' voor massa-uitrol: een netwerk-installatie bedoeld om op afstand tientallen laptops tegelijk te installeren (`docs/adr/0002-own-installer-iso.md`).
- **mijn-bureau-infra** installeert de samenwerkingssuite via Helmfile op een Kubernetes cluster. De standaard handleiding gaat uit van een **publieke server** op het internet met Let's Encrypt certificaten, een publiek domein en zware server-hardware (12 vCPU / 48 GiB RAM).

Iemand (zoals een CISO of beleidsadviseur) die *het totaalplaatje in actie wil zien*—op één lokale laptop, zónder publiek domein of ingewikkelde cloud-servers—moet dit nu allemaal handmatig in elkaar knutselen. Die ingewikkelde puzzel van NixOS, KVM, Ubuntu, K3s, lokale DNS, self-signed TLS en versiebeheer, is exact wat dit project oplost en automatiseert.

## Wat het toevoegt

1. **Eén systeem, één machine, één soepele stroom.** Opstarten, bevestigen, wachten en gebruiken. Geen externe servers of publieke domeinnamen nodig.
2. **De échte werkplek, geen simulatie.** Het geïnstalleerde systeem gebruikt exact hetzelfde DAWO-Core profiel als de echte pilot-laptops (`profiles-dawo-generic`). Dezelfde desktop, apps en verplichte beveiligingseisen. Onze toevoegingen draaien op de achtergrond; de werkelijke gebruikerservaring wordt niet aangepast (`docs/adr/0003-workplace-parity.md`).
3. **Reproduceerbaar en controleerbaar.** Exacte versies van DAWO, K3s, Ubuntu en alle container-images staan vast in het `manifest/appliance-manifest.json`, beveiligd met een cryptografische controle (checksum). Als twee gemeenten deze release bouwen, krijgen ze een 100% identiek resultaat.
4. **Standaard veilig.** De installer doet niets zonder expliciete toestemming. De standaard actie is een veilige "dry-run". Wachtwoorden worden pas tijdens de installatie lokaal gegenereerd; er staan geen geheimen in de broncode.
5. **Een brug voor integratie.** Dit project legt precies bloot waar de twee ecosystemen (DAWO en Mijn Bureau) elkaar nog niet soepel raken. Dit levert nuttige inzichten op voor de officiële projecten, zelfs als deze appliance nooit in productie gaat.

## Wat het níét is

- Geen officiële distributie van de Rijksoverheid.
- **Geen productieomgeving:** Het draait op één node, zonder back-ups en met tijdelijke certificaten (in v0.1). Zet hier géén echte (gevoelige) gemeentelijke productiedata op!
- Geen beheertool voor honderden laptops. (Massa-uitrol is de taak van DAWO-Sextant).
- Geen speeltuin voor complexe toekomstige wensen zoals Active Directory koppelingen of multi-node clusters. Dat valt buiten de scope van versie 0.1 (ADR 0001).

## Afwijkingen ten opzichte van de standaard (en waarom)

*(Voor de volledige technische lijst, zie `docs/deviations.md`)*

| Onderdeel | De officiële standaard | Deze appliance | Waarom? |
| --- | --- | --- | --- |
| **Installatie** | Massa-uitrol via netwerk (PXE/SSH) | Interactieve live USB-installer | Gemaakt voor één losse demonstratie-laptop (ADR 0002) |
| **Opslag** | Standaard met schijfversleuteling (LUKS) en TPM | Nog **geen LUKS** versleuteling in v0.1 | Houdt de demonstratie en installatie voor nu simpel |
| **Updates** | Automatische Codeberg updates op de achtergrond | Auto-update **uit** | De demonstrator is een vaste, reproduceerbare momentopname (ADR 0003) |
| **Inloggen** | Normaal inlogscherm | Automatisch inloggen als `dawo` met een welkomstscherm | Een demonstratie moet je kunnen bekijken zonder meteen wachtwoorden te typen |
| **Mijn Bureau** | Draait op een zware netwerkserver | Draait in een lokale Ubuntu VM op dezelfde laptop | "Digital Sovereignty in a Box" (alles lokaal op 1 machine) |
| **Beveiliging (TLS)** | Publieke certificaten (Let's Encrypt) | Lokaal gegenereerde (self-signed) certificaten en lokale DNS | We hebben geen publiek internetdomein nodig voor een lokale demo |

## Nadelen en de kosten van deze aanpak

- **Zware Hardware-eisen.** Mijn Bureau eist veel geheugen. De host heeft minimaal 32 GiB RAM nodig voor het `laptop-demo` profiel, en eigenlijk 64 GiB voor de volledige versie. Een standaard kantoorlaptop trekt dit niet.
- **Niet representatief voor de eindbeveiliging.** Zonder schijfversleuteling (LUKS) toont dit de *functionaliteit*, maar niet de geharde veiligheid van het definitieve overheidsproduct.
- **Versies lopen achter.** Omdat wij alle versies "vastpinnen", lopen we altijd iets achter op de nieuwste updates van de officiële projecten. 
- **Nog niet 100% soeverein.** Op de achtergrond worden er tijdens de installatie (build-fase) nog steeds componenten van Microsoft (GitHub) of Docker Hub gedownload. Dit is een landelijk probleem waaraan de officiële projecten nog werken.

## Wat betekent "Klaar" voor v0.1?

1. Start de `dawo-appliance-installer.iso` op. Een test-plan toont wat er gaat gebeuren zonder de schijf te wissen.
2. Na expliciete goedkeuring installeert het systeem de complete host.
3. Automatische login start de KDE Plasma desktop (exact gelijk aan de beveiligde DAWO pilot).
4. De Ubuntu virtuele machine start automatisch en installeert Mijn Bureau (met een nieuw, uniek wachtwoord).
5. De automatische systeemcontrole (health check) geeft groen licht en opent direct het dashboard in de browser op `https://bureaublad.dawo.internal`.
6. Alles gebeurt veilig op basis van de cryptografisch gecontroleerde bronnen in het `manifest/appliance-manifest.json`.

*Voortgang van deze doelen staat in `docs/roadmap.md`.*
