# Draaiboek: Tezza laten zien, met de zaaktypes van Súdwest-Fryslân

Dit draaiboek is voor wie Tezza laat zien vanaf de USB-SSD van de `dawo-appliance`: document- en zaakbeheer op Alfresco, met Open Zaak, en met de **eigen zaaktypes van Súdwest-Fryslân** (SWF), zoals die nu in de vakapplicaties worden gebruikt.

> **Let op:** dit is een experimentele, onofficiële demonstrator. Het is geen officiële distributie van DAWO, Mijn Bureau, Tezza of Contezza, en niet bedoeld voor productie. Tezza wordt bij het starten rechtstreeks bij Contezza gedownload; in de werkplek zelf zit er niets van. Op de kaart in de Launcher staat waarom Tezza rood is: niet alle onderdelen zijn open source.

---

## Voorbereiding

**De dag ervoor (eenmalig, ongeveer een uur):**

1. Start de laptop vanaf de USB-SSD: aanzetten, bij het logo **F12** (Dell) en kies de USB-SSD onder *UEFI*. Zorg voor internet (wifi of kabel).
2. De **Launcher** opent vanzelf. Klik bij **Tezza** op **Starten**.
3. De eerste keer downloadt Tezza ongeveer 8 GB en richt zich in: reken op **30 tot 45 minuten**. Je ziet op de kaart bij welke stap hij is. De stap "De zaaktypes van Súdwest-Fryslân laden" zet de 86 SWF-zaaktypes in Open Zaak.
4. Als de kaart **Klaar** zegt: klik op **Openen**, log in met **`launcher`** / **`launcher`** en maak één zaak aan (zie scenario 1). Daarmee weet je dat alles werkt, en de lijsten zijn op de dag zelf niet leeg.
5. Klik in de Launcher op **Stoppen** en zet de laptop uit. Alles wat gedownload en aangemaakt is, blijft op de USB-SSD.

**Op de dag zelf (15 minuten vóór de demo):**

1. Start de laptop vanaf de USB-SSD en klik bij Tezza op **Starten**. Nu duurt het ongeveer **5 minuten**.
2. Als de kaart **Klaar** zegt: **Openen**, inloggen met **`launcher`** / **`launcher`**.
3. Houd een Word-document bij de hand om te uploaden (bijvoorbeeld een conceptbeschikking).

---

## Scenario 1: Gehandicaptenparkeerkaart (5 minuten)

*Een burger vraagt een gehandicaptenparkeerkaart aan; de medewerker registreert de zaak, voegt de aanvraag toe en neemt hem in behandeling.*

1. **Maken → Registreer zaak.**
2. **Catalogus:** `SWF` (de verantwoordelijke organisatie wordt 823288444, Súdwest-Fryslân).
3. **Type:** `Gehandicaptenparkeerkaart`. Omschrijving: bijvoorbeeld "Parkeerkaart voor mevrouw De Vries".
4. Vink **Claim zaak** aan. *Bij de zaaktypes van SWF is een behandelaar verplicht; met "Claim zaak" word jij dat.* Klik **Registreer**.
5. De zaak opent, met een eigen zaaknummer en de geplande einddatum volgens de doorlooptijd van het zaaktype.
6. **Documenten → + → Bestand uploaden:** kies het Word-document. Kies als **documenttype** bijvoorbeeld `Beschikking`, geef een **titel** en klik **Ok**. Klik daarna op de bestandsnaam: Tezza zet het document om en toont het in de viewer.
7. **Zaakinformatie →** het statusicoon (rechts boven bij *Status*) → **Statustype** `In behandeling genomen`, met een korte omschrijving → **Ok**.
8. **Opmerkingen:** voeg een notitie toe, bijvoorbeeld "Aanvrager gebeld, stukken compleet".

**Gesprekspunten:** dit zijn de zaaktypes, statussen, documenttypes en resultaten zoals SWF ze zelf heeft vastgelegd, nu in Open Zaak (de landelijke standaard voor zaakgericht werken) en zichtbaar in Tezza.

## Scenario 2: Evenementenvergunning, van aanvraag tot besluit (5 minuten)

*Een aanvraag voor een braderie wordt afgehandeld.*

1. **Maken → Registreer zaak**, catalogus `SWF`, type `Evenementenvergunnning` (met dubbele n, zoals in de catalogus van SWF), omschrijving bijvoorbeeld "Braderie Bolsward". Vink **Claim zaak** aan en klik **Registreer**.
2. Voeg de aanvraag toe als document (documenttype `Aanvraag`) en open hem in de viewer.
3. Laat de werkvoorraad zien: **Mijn werkvoorraad** (de zaak staat op jouw naam), **Groepswerkvoorraad** en **Zaken**.
4. **Zoeken** (balk bovenaan): typ het zaaknummer. De zaak en zijn documentenmap komen naar voren.
5. **Afhandelen:** open de zaak, klik op het afhandelicoon (dubbel vinkje) → **Resultaat** `Verleend`, omschrijving → **Ok**. De zaak krijgt een einddatum; onder *Status* staan het resultaat en de archiefgegevens (selectielijstklasse, waardering, bewaartermijn).

**Gesprekspunten:** de archivering volgt uit het zaaktype: bij het resultaat staat meteen hoe lang de zaak bewaard wordt en of hij vernietigd of bewaard moet worden.

## Scenario 3: Aanvraag rijbewijs, het statusverloop (3 minuten)

*Hoe een zaak de stappen van een keten volgt.*

1. Registreer een zaak van het type `Aanvraag rijbewijs` (catalogus `SWF`, **Claim zaak** aanvinken).
2. Zet de status achter elkaar op `Aanvraag verstuurd naar RDW`, `Rijbewijs in productie` en `Gereed om af te halen op locatie Sneek` (of `Bolsward`).
3. Laat het statusoverzicht zien: elke stap met zijn datum.

**Let op:** bij dit zaaktype horen in de catalogus van SWF geen documenttypes; documenten toevoegen kan hier dus niet. Gebruik daarvoor scenario 1 of 2.

---

## Ook te laten zien

- **Postintake**, **Dossiers** (Maken → Registreer dossier) en **Objecten** (Maken → Registreer object): de formulieren openen.
- **Open Zaak beheer**: in de Launcher onder *Ook in deze omgeving*, login `launcher` / `launcher`. Daar staan de catalogus `SWF` en de zaaktypes zelf.

## Als iets hapert

| Wat je ziet | Wat te doen |
|---|---|
| Een nieuwe zaak staat niet meteen in **Zaken** | De zoekindex loopt na het starten even achter; na een minuut of twee staat hij er. In **Groepswerkvoorraad** staat hij meteen. |
| "Het is verplicht om ten minste één behandelaar…" | Vink **Claim zaak** aan (SWF-zaaktypes vragen een behandelaar). |
| Rechtsboven staat "Administrator Tezza" in plaats van "Launcher Demo" | Er was nog een sessie als admin. Avatar rechtsboven → **Afmelden**, en log opnieuw in als `launcher`. |
| De Launcher zegt **Starten mislukt** | Klik **Opnieuw proberen**. Lukt dat niet, dan staan de details in `tezza.txt` op de USB-SSD (partitie DAWO_LOGS). |
| Een andere omgeving draait nog | De andere kaarten zijn dan grijs. Stop eerst die omgeving; daarna kun je Tezza starten. |
