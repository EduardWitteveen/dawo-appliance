# Gemeentelijk 5-Minuten Pitch Script

Dit script is ontworpen voor Beleidsadviseurs of Innovatiemanagers die de `dawo-appliance` presenteren aan gemeentelijke beslissers (Wethouders, CISO's of Afdelingshoofden). Het benadrukt digitale soevereiniteit, risicovrij evalueren en de exacte open-source werkplekervaring.

**Voorbereiding:** Een test-laptop geprepareerd volgens de [hardware vereisten](demo-hardware.md) en een opstartbare USB-stick met de appliance ISO.

---

## 0:00 – 1:00 | Introductie & Veilig Opstarten
*Actie: Plaats de USB-stick en start de laptop op in de 'live' omgeving.*

**Gesprekspunten:**
- "We onderzoeken digitale soevereiniteit en willen onze afhankelijkheid van één leverancier (vendor lock-in zoals Microsoft 365) verminderen, in lijn met de landelijke VNG/BZK-richtlijnen."
- "Wat ik jullie nu laat zien is de DAWO (Digitale Autonome Werkplek Overheid) demonstrator. Dit draait volledig lokaal op deze afgeschreven machine."
- "Op dit moment draaien we een 'live' omgeving vanaf de USB. Dit is 100% veilig en overschrijft nog niets op de harde schijf. We kunnen dit zonder risico testen."

## 1:00 – 2:00 | Transparantie & Het Installatieplan
*Actie: Open de terminal en draai `dawo-appliance-bootstrap plan`.*

**Gesprekspunten:**
- "Vertrouwen en transparantie zijn de basis van open-source. Voordat we iets installeren, kan dit systeem een 'installatieplan' genereren."
- *Wijs naar de uitvoer op het scherm:* "Dit toont exact wat er gaat gebeuren. Er zijn geen verborgen processen, geen telemetrie en geen ongevraagde cloud-verbindingen."
- "Omdat deze hele werkplek in code (NixOS) is vastgelegd, is de inrichting bij elke gemeente exact reproduceerbaar. Geen handmatig beheer meer."

## 2:00 – 3:30 | De Werkplek Ervaring
*Actie: Start de geïnstalleerde laptop op (in de DAWO desktop).*

**Gesprekspunten:**
- "Dit is exact de werkomgeving die onze ambtenaren zouden zien. Het is schoon, toegankelijk en voelt vertrouwd aan."
- *Benoem de welkomstmelding:* "Je ziet hier staan dat het een 'experimentele' demonstrator is. Het toont de onderliggende techniek, niet de definitieve huisstijl van onze gemeente."
- "Alles wat je hier ziet, is gebaseerd op open standaarden. Wij hebben de volledige controle over de updates en de opslag van onze data."

## 3:30 – 5:00 | Mijn Bureau & Data Soevereiniteit
*Actie: Open de browser naar het lokale Mijn Bureau dashboard.*

**Gesprekspunten:**
- "Achter de schermen draait deze laptop nu zijn eigen lokale 'cloud' (via K3s Kubernetes). Wat je hier ziet is de 'Mijn Bureau' samenwerkingssuite."
- *Klik door Nextcloud, Collabora (office) of Grist (spreadsheets):* "Dit zijn volwaardige, open-source alternatieven voor OneDrive, Word en Excel."
- "Het cruciale verschil: **Al deze data blijft híer.** Als we hier een document typen of een spreadsheet maken, verlaat dit nooit ons gemeentelijke netwerk. Dit lost onze BIO-compliancy uitdagingen rondom cloud-data in één keer op."

---

## FAQ voor de Presentator

- **"Kunnen we dit koppelen aan onze Active Directory/Entra ID?"**
  *Antwoord:* Deze v0.1 demonstrator is standalone, maar de uiteindelijke productie-versies van DAWO ondersteunen uiteraard standaard federatieve identiteitskoppelingen (OIDC/SAML).
- **"Is het veilig?"**
  *Antwoord:* Het gebruikt cryptografisch beveiligde code en lokale orkestratie. Zaken als volledige schijfversleuteling (LUKS) zijn voor deze demo even uitgezet voor het gebruiksgemak, maar zijn standaard aanwezig in de productieversie.
- **"Hebben we hier speciale Linux-beheerders voor nodig?"**
  *Antwoord:* Nee, het onderliggende beheer is geautomatiseerd via code. Als dit centraal door een leverancier of samenwerkingsverband wordt ingericht, is de lokale uitrol en update-cyclus volledig gestandaardiseerd.
