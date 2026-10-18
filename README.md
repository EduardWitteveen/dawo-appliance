# dawo-appliance

**Een complete overheidswerkplek op een USB-schijf.** Steek hem in een laptop, zet hem aan en werk: bestanden, samen documenten bewerken, chatten en zaakgericht werken, zonder cloud. Er verandert niets op de laptop.

[![De Launcher start Mijn Bureau vanzelf: stap 10 van 17, klaar rond 17:26](docs/screenshots/live-launcher-progress.png)](docs/screenshots/live-launcher-progress.png)

## Zelf proberen

1. **Download** het schijfbestand (binnenkort, [#175](https://github.com/EduardWitteveen/dawo-appliance/issues/175)).
2. **Zet het op een USB-SSD** van 64 GB of meer, met [Rufus](https://rufus.ie) of [balenaEtcher](https://etcher.balena.io).
3. **Start de laptop van de USB-schijf.** De Launcher start Mijn Bureau vanzelf. Klaar? Klik **Openen** en log in met `dawo` / `dawo`.

Je hebt een laptop met 32 GB geheugen nodig. [Stap voor stap, met plaatjes →](docs/live-usb.md)

## Wat zit erin
---

### 🚀 Zelf proberen

**Een complete overheidswerkplek op een USB-schijf.** Steek hem in een laptop, zet de laptop aan, en je werkt met bestanden, documenten en chat, met één inlog, zonder cloud. Er verandert niets op de laptop zelf.

[![De Launcher start Mijn Bureau vanzelf: stap 10 van 17, nog ongeveer 11 minuten, klaar rond 17:26](docs/screenshots/live-launcher-progress.png)](docs/screenshots/live-launcher-progress.png)

<sub>Echte schermafbeelding van een testlaptop: na het inloggen start de **Launcher** Mijn Bureau vanzelf en laat zien bij welke stap hij is en wanneer hij klaar is.</sub>

**In drie stappen:**

1. **Download** het schijfbestand `dawo-appliance-live.img`. De eerste downloadbare versie komt binnenkort ([v0.1.0-rc.1, #175](https://github.com/EduardWitteveen/dawo-appliance/issues/175)); tot die tijd kun je het [zelf bouwen](docs/live-usb.md).
2. **Zet het op een USB-SSD** met [Rufus](https://rufus.ie) of [balenaEtcher](https://etcher.balena.io), zoals je dat met een Ubuntu-stick doet.
3. **Start de laptop van de USB-schijf** (bij een Dell met F12). Na het inloggen opent de Launcher en start **Mijn Bureau vanzelf** na één minuut. De eerste keer duurt dat een half uur tot een uur (alles wordt gedownload), daarna gaat het veel sneller. Is hij klaar, klik dan op **Openen** en log in met `launcher` / `launcher`.

**Wat heb je nodig?** Een laptop met 32 GB geheugen, een USB-SSD van 64 GB of meer, en internet bij de eerste start. Meer in [hardware-vereisten](docs/demo-hardware.md).

**Iets gezien, gaat iets mis, of heb je een idee?** Laat het ons weten via een [melding op GitHub](https://github.com/EduardWitteveen/dawo-appliance/issues/new). Elke reactie helpt: dit project wordt beter van mensen die het echt proberen.

---

### 🇳🇱 Voor Gemeenten en Overheidsinstellingen (NL)
*(English technical documentation continues below)*

Gemeenten worstelen met *vendor lock-in* (zoals Microsoft 365) en strenge BIO-eisen rond data in de cloud. Dit open-source project maakt digitale soevereiniteit tastbaar: **steek een USB-schijf in een gewone laptop, zet hem aan, en je werkt op een complete overheidswerkplek.** Er verandert niets op de laptop zelf.

Op de USB-schijf staat alles:
1. **De werkplek (DAWO):** het veilige Linux-bureaublad uit de BZK-pilots, met dezelfde programma's.
2. **De samenwerkingssuite (Mijn Bureau):** een lokaal draaiend alternatief voor OneDrive, Teams en Office (Nextcloud, Collabora, Element), met één inlog.

**Het grote voordeel:** alle documenten en data blijven op de USB-schijf. Er gaat geen byte naar commerciële cloud-providers.

#### In beeld (echte schermafbeeldingen van een testlaptop)

| Mijn Bureau installeert zichzelf | De voortgang, stap voor stap |
| --- | --- |
| [![De statuspagina terwijl Mijn Bureau zijn apps installeert: draaiend symbool, laatste activiteit en de laatste regel van het logboek](docs/screenshots/live-status-deploying.png)](docs/screenshots/live-status-deploying.png) | [![De statuspagina als Mijn Bureau klaar is: alle onderdelen groen en een knop Open Mijn Bureau](docs/screenshots/live-status-page-dell.png)](docs/screenshots/live-status-page-dell.png) |
| Na het opstarten opent een statuspagina die laat zien wat werkt en waar het systeem op wacht. | Alle 14 stappen lukten op de testlaptop, in ongeveer 8 minuten. Daarna opent de knop Mijn Bureau. |

| Inloggen, één keer | Het dashboard Mijn Bureaublad |
| --- | --- |
| [![Het inlogscherm van Mijn Bureau met gebruikersnaam dawo](docs/screenshots/live-login-dell.png)](docs/screenshots/live-login-dell.png) | [![Het dashboard Mijn Bureaublad na het inloggen, met tabbladen voor Element en Nextcloud](docs/screenshots/live-bureaublad-dell.png)](docs/screenshots/live-bureaublad-dell.png) |
| Inloggen met `launcher` / `launcher`. Deze ene inlog geldt voor alle apps. | Het startpunt: van hieruit open je bestanden en chat. |
| **Bestanden (Nextcloud)** | **Chat (Element)** |
| [![Nextcloud Bestanden, nog leeg, na het inloggen via Mijn Bureau](docs/screenshots/live-nextcloud-dell.png)](docs/screenshots/live-nextcloud-dell.png) | [![Element chat met het welkomstscherm voor DAWO Demo en de ruimte welkom](docs/screenshots/live-element-dell.png)](docs/screenshots/live-element-dell.png) |
| Het alternatief voor OneDrive. | Het alternatief voor Teams-chat, op de open standaard Matrix. |
| **Documenten bewerken (Collabora)** | |
| [![Een Word-document dat in de browser wordt bewerkt met Collabora Online, geopend vanuit Nextcloud](docs/screenshots/live-collabora-dell.png)](docs/screenshots/live-collabora-dell.png) | |
| Een Word-document maken en bewerken in de browser, vanuit Nextcloud. De menu's zijn nog Engels ([#180](https://github.com/EduardWitteveen/dawo-appliance/issues/180)). | |

<sub>Gemaakt door de debug-modus van de USB-schijf op een Dell Latitude 5550, alleen bijgesneden (herkomst: [`docs/screenshots/HARDWARE.md`](docs/screenshots/HARDWARE.md)).</sub>

#### Stand van zaken (15 oktober 2026)

| | |
| --- | --- |
| [![Inloggen, één keer voor alles](docs/screenshots/live-login-dell.png)](docs/screenshots/live-login-dell.png) **Eén keer inloggen** voor alles | [![Het dashboard Mijn Bureaublad](docs/screenshots/live-bureaublad-dell.png)](docs/screenshots/live-bureaublad-dell.png) **Mijn Bureaublad**, het startpunt |
| [![Bestanden in Nextcloud](docs/screenshots/live-nextcloud-dell.png)](docs/screenshots/live-nextcloud-dell.png) **Bestanden** (Nextcloud) | [![Een document bewerken in Collabora](docs/screenshots/live-collabora-dell.png)](docs/screenshots/live-collabora-dell.png) **Samen documenten bewerken** (Collabora) |
| [![Chat in Element](docs/screenshots/live-element-dell.png)](docs/screenshots/live-element-dell.png) **Chatten** (Element) | **Binnenkort in de Launcher:** Valtimo (zaakgericht werken), Nextcloud Common Ground (Conduction-apps) en Tezza |

<sub>Echte schermafbeeldingen van een testlaptop ([herkomst](docs/screenshots/HARDWARE.md)).</sub>

## Meer weten

- **Voor gemeenten:** waarom dit bestaat, wat werkt, wat je nodig hebt en veelgestelde vragen: [voor-gemeenten](docs/audience/voor-gemeenten.md)
- **Wat elke app doet:** [rondleiding langs de apps](docs/audience/mijn-bureau-apps.md)
- **Iets gezien of een idee?** [Laat het weten op GitHub](https://github.com/EduardWitteveen/dawo-appliance/issues/new)
- **Technical documentation (English):** [technical overview](docs/technical-overview.md) · [all documents](docs/README.md)

> **Experimenteel en onofficieel.** Een onafhankelijk experiment, geen officiële DAWO-, Mijn Bureau- of BZK-distributie. Niet voor productie. Licentie: [EUPL-1.2](LICENSE).
