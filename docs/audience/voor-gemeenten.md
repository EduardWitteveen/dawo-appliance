# DAWO-werkplek op een USB-schijf: voor gemeenten

> Experimenteel en onofficieel. Terug naar de [voorpagina](../../README.md).


Gemeenten worstelen met *vendor lock-in* (zoals Microsoft 365) en strenge BIO-eisen rond data in de cloud. Dit open-source project maakt digitale soevereiniteit tastbaar: **steek een USB-schijf in een gewone laptop, zet hem aan, en je werkt op een complete overheidswerkplek.** Er verandert niets op de laptop zelf.

Op de USB-schijf staat alles:
1. **De werkplek (DAWO):** het veilige Linux-bureaublad uit de BZK-pilots, met dezelfde programma's.
2. **De samenwerkingssuite (Mijn Bureau):** een lokaal draaiend alternatief voor OneDrive, Teams en Office (Nextcloud, Collabora, Element), met één inlog.

**Het grote voordeel:** alle documenten en data blijven op de USB-schijf. Er gaat geen byte naar commerciële cloud-providers.

#### In beeld (echte schermafbeeldingen van een testlaptop)

| Mijn Bureau installeert zichzelf | De voortgang, stap voor stap |
| --- | --- |
| [![De statuspagina terwijl Mijn Bureau zijn apps installeert: draaiend symbool, laatste activiteit en de laatste regel van het logboek](../screenshots/live-status-deploying.png)](../screenshots/live-status-deploying.png) | [![De statuspagina als Mijn Bureau klaar is: alle onderdelen groen en een knop Open Mijn Bureau](../screenshots/live-status-page-dell.png)](../screenshots/live-status-page-dell.png) |
| Na het opstarten opent een statuspagina die laat zien wat werkt en waar het systeem op wacht. | Alle 14 stappen lukten op de testlaptop, in ongeveer 8 minuten. Daarna opent de knop Mijn Bureau. |

| Inloggen, één keer | Het dashboard Mijn Bureaublad |
| --- | --- |
| [![Het inlogscherm van Mijn Bureau met gebruikersnaam dawo](../screenshots/live-login-dell.png)](../screenshots/live-login-dell.png) | [![Het dashboard Mijn Bureaublad na het inloggen, met tabbladen voor Element en Nextcloud](../screenshots/live-bureaublad-dell.png)](../screenshots/live-bureaublad-dell.png) |
| Inloggen met `launcher` / `launcher`. Deze ene inlog geldt voor alle apps. | Het startpunt: van hieruit open je bestanden en chat. |
| **Bestanden (Nextcloud)** | **Chat (Element)** |
| [![Nextcloud Bestanden, nog leeg, na het inloggen via Mijn Bureau](../screenshots/live-nextcloud-dell.png)](../screenshots/live-nextcloud-dell.png) | [![Element chat met het welkomstscherm voor DAWO Demo en de ruimte welkom](../screenshots/live-element-dell.png)](../screenshots/live-element-dell.png) |
| Het alternatief voor OneDrive. | Het alternatief voor Teams-chat, op de open standaard Matrix. |
| **Documenten bewerken (Collabora)** | |
| [![Een Word-document dat in de browser wordt bewerkt met Collabora Online, geopend vanuit Nextcloud](../screenshots/live-collabora-dell.png)](../screenshots/live-collabora-dell.png) | |
| Een Word-document maken en bewerken in de browser, vanuit Nextcloud. De menu's zijn nog Engels ([#180](https://github.com/EduardWitteveen/dawo-appliance/issues/180)). | |

<sub>Gemaakt door de debug-modus van de USB-schijf op een Dell Latitude 5550, alleen bijgesneden (herkomst: [`docs/screenshots/HARDWARE.md`](../screenshots/HARDWARE.md)).</sub>

#### Stand van zaken (18 oktober 2026)

| | |
| --- | --- |
| ✅ **Werkt** | Opstarten van USB zonder de laptop te veranderen · werkplek na 20 seconden · gegevens blijven bewaard op de USB-schijf · netjes afsluiten |
| ✅ **Werkt** | **De Launcher**: na het inloggen één venster met een kaart per omgeving, een balk voor de hele start en een voor de huidige stap, de verwachte eindtijd en wat hij nu doet; daarna **Openen**. Er draait één omgeving tegelijk |
| ✅ **Werkt** | **Vier omgevingen**, op de testlaptop allemaal tot "klaar" gekomen: **Mijn Bureau** (bestanden, documenten, chat), **Valtimo** met Open Zaak en een burgerformulier (zaakgericht werken), **Nextcloud Common Ground** (de apps van Conduction, met demozaken) en **Tezza** (documenten en archief) |
| ✅ **Werkt** | Overal dezelfde demo-inlog: `launcher` / `launcher` |
| ✅ **Werkt** | **Rondgang**: een minuut na het inloggen start de Launcher de omgevingen om de beurt, elk vijf minuten, en houdt een verslag bij. Zo test de laptop zichzelf terwijl niemand kijkt |
| ⏭️ **Daarna** | Eerste testversie (v0.1.0-rc.1) om te downloaden ([#175](https://github.com/EduardWitteveen/dawo-appliance/issues/175)) |

De technische details staan in de [technische uitleg](../technical-overview.md) (Engels) en in de [issues op GitHub](https://github.com/EduardWitteveen/dawo-appliance/issues).

#### Wat heb je nodig?

- Een laptop met **32 GB geheugen** en virtualisatie aan in de BIOS (met minder start alleen de werkplek; de Launcher waarschuwt vooraf).
- Een **USB-SSD van 64 GB of meer**, liefst USB 3. Een gewone USB-stick is te klein, te traag en slijt snel van het schrijfwerk.
- **Internet** bij de eerste start van een omgeving: die downloadt dan zijn onderdelen (van een paar minuten tot ruim een half uur, Tezza ongeveer 6 GB).
- Meer: [hardware-vereisten](../demo-hardware.md) en [de USB-schijf maken](../live-usb.md).

Wat elke app van Mijn Bureau doet, zie je in de [rondleiding langs de apps](mijn-bureau-apps.md). Hoe de onderdelen samenhangen en waar je gegevens staan, lees je in de [functionele architectuur](functionele-architectuur.md).

#### Veelgestelde vragen

- **Is dit officieel?** Nee. Het is een onafhankelijk experiment (v0.1), gebouwd op de officiële broncode van DAWO en Mijn Bureau, maar geen officiële DAWO-, Mijn Bureau- of BZK-distributie.
- **Kan dit morgen in productie?** Nee. Het is bedoeld om uit te proberen en te laten zien. De demo-wachtwoorden zijn openbaar en de schijf is niet versleuteld.
- **Kan ik een gewone USB-stick van 4 of 8 GB gebruiken?** Nee. De werkplek alleen is al ongeveer 6 GB, en de omgevingen schrijven veel. Gebruik een USB-SSD van 64 GB of meer; een gewone stick is ook veel te traag en raakt snel versleten.
- **Het is traag van USB.** Gebruik een USB-SSD op een USB 3-poort. De eerste start van een omgeving is altijd het langst, omdat hij dan alles downloadt; daarna gaat het veel sneller.
- **Verandert er iets aan mijn laptop?** Nee. De laptop start van de USB-schijf en alles wordt op die schijf bewaard. Haal je hem eruit, dan start de laptop weer zoals altijd.
- **Welke laptop werkt?** Getest op een Dell Latitude 5550 met 32 GB. Een andere laptop met 32 GB, een Intel- of AMD-processor en virtualisatie aan zou ook moeten werken; laat het weten als het niet lukt.
- **Wat is de Launcher?** Een venster dat na het inloggen opent, met een kaart per omgeving: starten, stoppen, voortgang en openen. Er is ook een opdracht voor de terminal: `launch` (lijst), `launch valtimo` (starten), `launch --status`. Een omgeving wordt pas gedownload als je hem start; er draait er één tegelijk.
- **Zijn alle omgevingen open source?** Mijn Bureau, Valtimo, Open Zaak, Open Formulieren en de apps van Conduction wel (EUPL of AGPL). Bij **Tezza** is de licentie onduidelijk: Tezza noemt zichzelf open source onder de EUPL, maar in de broncode staat geen licentie en de broncode van deze versie hebben we niet openbaar gevonden. Daarom zit er niets van Tezza op de USB-schijf: het wordt pas bij het starten bij Contezza gedownload, na een rode melding.
- **Hoe lever ik feedback, of wil ik meetesten?** Graag! Maak een [melding op GitHub](https://github.com/EduardWitteveen/dawo-appliance/issues/new) of reageer in de DAWO-groepen. Vertel welke laptop je gebruikt en wat er gebeurde; de logbestanden staan op de USB-schijf (de partitie `DAWO_LOGS`).
- **Kan mijn organisatie hier een eigen omgeving aan toevoegen?** Ja, dat is het idee van de Launcher: een omgeving is een korte beschrijving plus de standaard demo-opzet van de leverancier. Zie [environments](../../environments/README.md) (Engels).
