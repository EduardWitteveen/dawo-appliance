# dawo-appliance

**Een complete overheidswerkplek op een USB-schijf.** Steek hem in een laptop, zet hem aan en werk: bestanden, samen documenten bewerken, chatten en zaakgericht werken, zonder cloud. Er verandert niets op de laptop.

[![De Launcher met vier omgevingen: Mijn Bureau wordt gestart, stap 5 van 17](docs/screenshots/live-launcher-four.png)](docs/screenshots/live-launcher-four.png)

## Zelf proberen

1. **Download** het schijfbestand [`dawo-appliance-live.img`](https://sourceforge.net/projects/dawo-appliance/files/v0.1.0-rc.1/dawo-appliance-live.img/download) (versie 0.1.0-rc.1, 6,9 GB, via SourceForge) en controleer de [SHA-256](https://sourceforge.net/projects/dawo-appliance/files/v0.1.0-rc.1/) ([hoe](docs/live-usb.md)).
2. **Zet het op een USB-SSD** van 64 GB of meer, met [Rufus](https://rufus.ie) of [balenaEtcher](https://etcher.balena.io).
3. **Start de laptop van de USB-schijf.** De Launcher opent; kies een omgeving en klik **Starten**, of laat hem na een minuut vanzelf alle omgevingen om de beurt starten. Klaar? Klik **Openen**.

Je hebt een laptop met 32 GB geheugen nodig. Overal log je in met `launcher` / `launcher`. [Stap voor stap, met plaatjes →](docs/live-usb.md)

## Wat zit erin

| | |
| --- | --- |
| [![Inloggen, één keer voor alles](docs/screenshots/live-login-dell.png)](docs/screenshots/live-login-dell.png) **Eén keer inloggen** voor alles | [![Het dashboard Mijn Bureaublad](docs/screenshots/live-bureaublad-dell.png)](docs/screenshots/live-bureaublad-dell.png) **Mijn Bureaublad**, het startpunt |
| [![Bestanden in Nextcloud](docs/screenshots/live-nextcloud-dell.png)](docs/screenshots/live-nextcloud-dell.png) **Bestanden** (Nextcloud) | [![Een document bewerken in Collabora](docs/screenshots/live-collabora-dell.png)](docs/screenshots/live-collabora-dell.png) **Samen documenten bewerken** (Collabora) |
| [![Chat in Element](docs/screenshots/live-element-dell.png)](docs/screenshots/live-element-dell.png) **Chatten** (Element) | [![De opdracht launch in een terminal: vier omgevingen, een controle en de status](docs/screenshots/live-launch-cli.png)](docs/screenshots/live-launch-cli.png) **Ook vanaf de opdrachtregel:** `launch` |

**Meer omgevingen in de Launcher.** Elk gebruikt de standaard demo van de leverancier en wordt pas gedownload als je hem start.

| | |
| --- | --- |
| [![De Valtimo-kaart: klaar, met daaronder Open Zaak, Objecten, Open Formulieren en Keycloak en hun logins](docs/screenshots/live-valtimo-card.png)](docs/screenshots/live-valtimo-card.png) **Valtimo** (zaakgericht werken) met Open Zaak, Objecten en Open Notificaties; de onderdelen staan met hun login op de kaart | [![Het burgerformulier: controleer en bevestig je aanvraag](docs/screenshots/live-burgerformulier.png)](docs/screenshots/live-burgerformulier.png) **Een burgerformulier** (Open Formulieren), inloggen met de DigiD-simulatie |
| [![Dossiq in Nextcloud: dashboard met open zaken, termijnen en taken](docs/screenshots/live-dossiq.png)](docs/screenshots/live-dossiq.png) **Nextcloud Common Ground**: de apps van Conduction, zoals Dossiq, gevuld met demozaken | [![Tezza Beheer na het inloggen](docs/screenshots/live-tezza-beheer.png)](docs/screenshots/live-tezza-beheer.png) **Tezza** (documenten en archief); let op: de licentie is onduidelijk, de Launcher waarschuwt eerst ([waarom](docs/audience/voor-gemeenten.md#veelgestelde-vragen)) |

<sub>Echte schermafbeeldingen van een testlaptop ([herkomst](docs/screenshots/HARDWARE.md)).</sub>

## Meer weten

- **Voor gemeenten:** waarom dit bestaat, wat werkt, wat je nodig hebt en veelgestelde vragen: [voor-gemeenten](docs/audience/voor-gemeenten.md)
- **Wat elke app doet:** [rondleiding langs de apps](docs/audience/mijn-bureau-apps.md)
- **Iets gezien of een idee?** [Laat het weten op GitHub](https://github.com/EduardWitteveen/dawo-appliance/issues/new)
- **Technical documentation (English):** [technical overview](docs/technical-overview.md) · [all documents](docs/README.md)

> **Experimenteel en onofficieel.** Een onafhankelijk experiment, geen officiële DAWO-, Mijn Bureau- of BZK-distributie. Niet voor productie. Licentie: [EUPL-1.2](LICENSE).
