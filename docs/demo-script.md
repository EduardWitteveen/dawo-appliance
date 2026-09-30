# Demoscript: vijf minuten DAWO appliance

Dit script is voor wie de `dawo-appliance` laat zien aan gemeentelijke beslissers (wethouders, CISO's, afdelingshoofden, informatiemanagers). Het laat zien dat een complete, open-source werkplek met samenwerkingssuite lokaal op één laptop kan draaien, zonder die laptop te veranderen.

> **Let op:** dit is een experimentele, onofficiële demonstrator. Het is geen officiële distributie van DAWO, Mijn Bureau of het Ministerie van BZK, en niet bedoeld voor productie. Zeg dat er ook bij.

---

## Voorbereiding (10 minuten vóór de demo)

- Een laptop volgens de [hardware-vereisten](demo-hardware.md): 32 GB geheugen, virtualisatie aan, Secure Boot uit (zie [de USB-schijf maken](live-usb.md)).
- De **USB-SSD** met de appliance. Gebruik geen gewone USB-stick: die slijt te snel.
- **Internet** (wifi of kabel). De eerste keer downloadt Mijn Bureau zijn apps. Daarna staan die op de USB-SSD en gaat het sneller.
- Start de laptop **ongeveer 10 minuten van tevoren**: USB-SSD erin, aanzetten, bij het logo **F12** (Dell) en kies de USB-SSD onder *UEFI*. De werkplek staat er na zo'n 20 seconden, Mijn Bureau is na ongeveer 8 minuten klaar. Je volgt dat op de statuspagina die vanzelf opent.
- Als Mijn Bureau klaar is: klik op **Open Mijn Bureau**, log in met gebruikersnaam **`dawo`** en wachtwoord **`dawo`**, en open vanuit het dashboard één keer Nextcloud en Element. Dan hoef je tijdens de demo niet meer in te loggen.
- Laat de statuspagina als eerste tabblad openstaan.

---

## 0:00 – 1:00 | Introductie: niets aan de laptop veranderd

*Actie: laat de laptop zien met de USB-SSD erin.*

**Gesprekspunten:**
- "We onderzoeken hoe we minder afhankelijk kunnen worden van één leverancier. Dit is een demonstrator van een digitale werkplek voor de overheid, gebouwd op open source: DAWO voor de werkplek, Mijn Bureau voor het samenwerken."
- "Deze laptop start van deze USB-schijf. De harde schijf van de laptop blijft onaangeroerd: haal je de USB-schijf eruit, dan start de laptop weer gewoon zoals voorheen."
- "Alles wat je gaat zien, draait hier op deze laptop zelf."

## 1:00 – 2:00 | De statuspagina: wat werkt er en waar wacht het op

*Actie: toon het tabblad "DAWO appliance — klaar".*

**Gesprekspunten:**
- "Na het opstarten opent deze pagina vanzelf. Je ziet per onderdeel of het werkt: internet, opslag, de virtuele machine en Mijn Bureau."
- "Achter de schermen start de laptop een eigen kleine 'cloud': een virtuele machine met Kubernetes (K3s). Daarin installeert Mijn Bureau zichzelf, in 14 stappen."
- "Elke versie van elk onderdeel ligt vast in de broncode. Bouw je de USB-schijf opnieuw, dan krijg je precies hetzelfde. Dat is controleerbaar, zonder verborgen handwerk."

## 2:00 – 3:00 | De werkplek

*Actie: laat het bureaublad zien (de KDE Plasma-werkplek van DAWO) en open het startmenu.*

**Gesprekspunten:**
- "Dit is de werkplek die een medewerker ziet: een gewone, overzichtelijke desktop met een browser, bestanden en instellingen."
- "Het is de technische basis van DAWO, niet de huisstijl van een gemeente. Kleuren en logo's kun je later zelf inrichten."

## 3:00 – 4:30 | Mijn Bureau: samenwerken met één inlog

*Actie: ga naar het tabblad **Mijn Bureaublad**.*

**Gesprekspunten:**
- "Dit is Mijn Bureau, de samenwerkingssuite. Eén keer inloggen geeft toegang tot alle apps."
- *Klik op **NextCloud**:* "Hier staan bestanden, het alternatief voor OneDrive. Documenten openen in Collabora, een open-source kantoorpakket in de browser."
- *Ga naar het tabblad **Element**:* "En dit is chat, het alternatief voor Teams-chat, gebouwd op de open standaard Matrix."
- "Deze apps en je gegevens draaien op deze laptop, op de USB-schijf. Ze staan niet bij een clouddienst."

## 4:30 – 5:00 | Afronding

**Gesprekspunten:**
- "Wat je zag: een complete werkplek met samenwerkingssuite, op één laptop, in een kwartier klaar, zonder de laptop te veranderen."
- "Het is een experiment om te laten zien wat er kan. Het is nog geen product: er is bijvoorbeeld geen schijfversleuteling en geen koppeling met ons eigen accountbeheer."
- "De broncode en de voortgang zijn openbaar, op GitHub."

---

## Vragen die je kunt verwachten

- **"Kunnen we dit koppelen aan onze Active Directory of Entra ID?"**
  *Antwoord:* Niet in deze demonstrator: die heeft één lokale demogebruiker. Mijn Bureau gebruikt Keycloak voor het inloggen, en Keycloak kan in principe koppelen met bestaande accountsystemen. Dat is hier niet gebouwd en niet getest.
- **"Is het veilig?"**
  *Antwoord:* Het is een demo, niet voor echte gegevens. Er is geen schijfversleuteling, de wachtwoorden zijn bewust eenvoudig en staan leesbaar op de machine. De statuspagina zegt dat ook. Wel liggen alle versies vast en is alles na te bouwen uit de openbare broncode.
- **"Werkt dit zonder internet?"**
  *Antwoord:* Tijdens het gebruik draaien de apps lokaal. De eerste keer is internet nodig om de apps te downloaden. Een volledig offline installatie valt buiten deze versie.
- **"Hebben we hier speciale Linux-beheerders voor nodig?"**
  *Antwoord:* De inrichting staat volledig in code en is reproduceerbaar. Hoe beheer er in de praktijk uitziet, bijvoorbeeld centraal via een samenwerkingsverband, is een vraag voor later. Deze demonstrator beantwoordt die niet.
- **"Is dit officieel DAWO of Mijn Bureau?"**
  *Antwoord:* Nee. Het is een onofficieel experiment dat de openbare onderdelen van DAWO en Mijn Bureau combineert, elk op een vaste versie.
