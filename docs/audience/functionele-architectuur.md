# Functionele architectuur: hoe de appliance als geheel werkt

*Eerste opzet (issue #162). Voor architecten, informatiemanagers en functioneel beheerders die willen begrijpen hoe de onderdelen samenhangen, zonder de techniek zelf te hoeven kennen. De technische uitwerking staat in het Engelse [`architecture.md`](../architecture.md).*

> Experimenteel en onofficieel: dit is geen distributie van DAWO, Mijn Bureau of het Ministerie van BZK, en niet bedoeld voor productie of echte gegevens.

**De vraag die dit document beantwoordt:** hoe werkt deze appliance als overheidswerkplek, waar staan de gegevens, en hoe vormen de losse onderdelen één geheel?

---

## 1. De onderdelen in gewone woorden

| Onderdeel | Wat het doet | Vergelijkbaar met |
| --- | --- | --- |
| **USB-SSD** | Bevat het hele systeem én bewaart de gegevens. De laptop zelf wordt niet gebruikt voor opslag. | Een draagbare werkplek in je tas |
| **DAWO-werkplek** | Het bureaublad dat de medewerker ziet: vensters, startmenu, browser, bestanden. Gebouwd op DAWO-Core (NixOS met KDE Plasma). | Windows op een werkplek |
| **Lokale 'cloud'** | Een afgeschermde virtuele machine (Ubuntu) op dezelfde laptop, met daarin Kubernetes (K3s). Hier draaien de samenwerkingsapps. | Het datacenter of de clouddienst, maar dan in de laptop |
| **Mijn Bureau** | De samenwerkingssuite: dashboard, bestanden, kantoorpakket en chat, met één inlog. | Microsoft 365 |
| **Statuspagina** | Laat na het opstarten zien wat werkt en waar het systeem op wacht. | Een dashboard voor de beheerder |

De apps binnen Mijn Bureau in deze demo:

| App | Functie | Alternatief voor |
| --- | --- | --- |
| **Keycloak** | Inloggen, één keer voor alle apps | Entra ID / Active Directory-inlog |
| **Mijn Bureaublad** | Startpagina met overzicht en links naar de apps | Het Microsoft 365-portaal |
| **Nextcloud** | Bestanden opslaan en delen | OneDrive / SharePoint |
| **Collabora** | Documenten, spreadsheets en presentaties bewerken in de browser | Word, Excel, PowerPoint online |
| **Element** (met Matrix/Synapse) | Chat | Teams-chat |

Mijn Bureau kent meer apps (zoals Grist, Docs en Meet). Die staan in deze demo uit, zodat alles op één laptop met 32 GB geheugen past ([ADR 0007](../adr/0007-mijn-bureau-laptop-profile.md)).

## 2. Hoe DAWO en Mijn Bureau zich tot elkaar verhouden

DAWO is de **werkplek**: wat er op het apparaat van de medewerker draait. Mijn Bureau is de **samenwerkingsdienst**: de apps die je via de browser gebruikt en die normaal centraal in een datacenter draaien. In deze appliance draaien ze allebei op dezelfde laptop. De werkplek is een gewone gebruiker van Mijn Bureau, precies zoals een laptop op kantoor een gebruiker is van een centrale dienst.

```
┌──────────────────────── Laptop (gestart van de USB-SSD) ────────────────────────┐
│                                                                                 │
│   DAWO-werkplek (bureaublad)                                                    │
│   ┌───────────────────────────┐                                                 │
│   │ Browser ── statuspagina   │                                                 │
│   │    │                      │                                                 │
│   └────┼──────────────────────┘                                                 │
│        │  https://…dawo.internal  (alleen binnen de laptop bereikbaar)          │
│        ▼                                                                        │
│   ┌──────────── Lokale 'cloud': virtuele machine met Kubernetes ─────────────┐  │
│   │                                                                          │  │
│   │   Keycloak (inloggen)                                                    │  │
│   │      │ één inlog voor:                                                   │  │
│   │      ├── Mijn Bureaublad (dashboard)                                     │  │
│   │      ├── Nextcloud (bestanden) ── Collabora (documenten bewerken)        │  │
│   │      └── Element + Matrix (chat)                                         │  │
│   │                                                                          │  │
│   └──────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
└────────────────────────────── gegevens: op de USB-SSD ──────────────────────────┘
```

## 3. De gebruikersreis

1. **USB-SSD erin, laptop aan.** Via het opstartmenu (bij een Dell: F12) kies je de USB-SSD. De harde schijf van de laptop wordt niet gebruikt en niet veranderd.
2. **Werkplek na ongeveer 20 seconden.** De medewerker `dawo` is automatisch ingelogd. De statuspagina opent vanzelf.
3. **Lokale cloud na ongeveer een minuut.** De virtuele machine en Kubernetes starten op de achtergrond.
4. **Mijn Bureau na ongeveer 8 minuten.** Mijn Bureau installeert zichzelf in 14 stappen; de statuspagina toont de voortgang. De allereerste keer duurt het langer, omdat de apps dan nog gedownload worden.
5. **Aan het werk.** Klik op *Open Mijn Bureau* en log in (demo: `dawo` / `dawo`). Vanaf het dashboard open je bestanden, documenten en chat zonder opnieuw in te loggen.
6. **Afsluiten en USB-SSD eruit.** De laptop is weer zoals hij was. De volgende keer start alles met de bewaarde gegevens.

## 4. De datareis: waar staat een document?

Stel: een medewerker maakt in Nextcloud een document en bewerkt het in Collabora.

1. De **browser** op de werkplek stuurt het document naar **Nextcloud**, via een versleutelde verbinding (HTTPS) die de laptop niet verlaat.
2. **Collabora** opent het document om het te bewerken en haalt het daarvoor bij Nextcloud op, ook binnen de laptop.
3. Nextcloud slaat het document op in de **virtuele machine**.
4. De schijf van die virtuele machine is een bestand op de **USB-SSD** (in de map `dawo-images`). Daar staat het document dus fysiek.

Op de USB-SSD staan:

| Wat | Waar | Blijft bewaard? |
| --- | --- | --- |
| Het systeem zelf (werkplek) | het opstartdeel van de USB-SSD | alleen-lezen; bij elke start hetzelfde |
| Documenten, chats, instellingen van de apps | de schijf van de virtuele machine (`dawo-images`) | ja |
| Sleutels en het eigen certificaat van deze appliance | een klein bestand `dawo-data.ext4` | ja |
| Bestanden in de thuismap van het bureaublad | het werkgeheugen | **nee**, weg na uitzetten. Gebruik Nextcloud |
| Logboeken en schermafbeeldingen (debug-modus) | het deel `DAWO_LOGS` | ja; bedoeld voor de ontwikkelaars |

**Let op:** de USB-SSD is niet versleuteld. Wie de schijf heeft, kan de gegevens lezen. In de debug-modus staan er ook schermafbeeldingen op, inclusief wat er op het scherm stond. Gebruik de demo daarom niet voor echte gegevens.

## 5. Wat betekent 'lokaal' hier precies?

**Lokaal, binnen de laptop:**
- Alle apps draaien op de laptop zelf, in de virtuele machine.
- Alle gegevens staan op de USB-SSD.
- **Inloggen gebeurt lokaal**, bij Keycloak in de virtuele machine. Er is geen koppeling met een extern accountsysteem, en er gaat geen inlog naar een clouddienst.
- De adressen van de apps (zoals `bureaublad.dawo.internal`) werken alleen binnen deze laptop. `.internal` is een domein dat nooit op internet bestaat.
- De versleutelde verbindingen gebruiken een eigen certificaat dat bij de eerste start op deze appliance wordt gemaakt. Het staat niet in de broncode en is voor elke USB-SSD anders.

**Wel internet nodig:**
- **De eerste keer**, om de apps van Mijn Bureau te downloaden (enkele gigabytes, ongeveer 10 minuten). Daarna staan ze op de USB-SSD.
- Bij elke start installeert Mijn Bureau zichzelf opnieuw en controleert dan online de onderdelen. Zonder internet start Mijn Bureau in deze versie niet. Een volledig offline werkende versie valt buiten de huidige opzet.

**Niet:**
- Er gaan geen documenten, chats of inloggegevens naar een clouddienst.
- Er is geen telemetrie van het project zelf. (Van de losse open-source apps is niet per app nagegaan of ze iets naar buiten sturen.)

## 6. Wat dit document (nog) niet beschrijft

- Hoe dit er in een echte gemeentelijke omgeving uitziet, met centrale servers, bestaande accounts en beheer. Zie voor een eerste verkenning [`integratie-visie.md`](integratie-visie.md).
- De technische details per onderdeel: zie [`architecture.md`](../architecture.md) en de besluiten in [`docs/adr/`](../adr/).

*Feedback op deze opzet is welkom op [issue #162](https://github.com/EduardWitteveen/dawo-appliance/issues/162).*
