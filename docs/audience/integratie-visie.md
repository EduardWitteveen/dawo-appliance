# Integratie- en beheervisie

*Voor de IT-Manager en Enterprise Architect*

Een veelvoorkomende zorg bij de overstap naar een open-source landschap zoals DAWO, is de vrees voor "onbeheerbare Linux-laptops" of het verbreken van de huidige identiteits-infrastructuur. Dit document verheldert kort hoe de beheer- en integratie-architectuur werkt in het DAWO/Mijn Bureau ecosysteem.

## 1. Identiteitsbeheer en SSO (Active Directory / Entra ID)

De demonstrator (`dawo-appliance`) gebruikt voor de eenvoud een lokale 'Mijn Bureau' account. Echter, de onderliggende software (Keycloak) is enterprise-ready.

- **Geen extra inlog-silo's:** In een productie-omgeving wordt Keycloak (de identiteitsmakelaar van Mijn Bureau) via standaard protocollen (**SAML 2.0** of **OIDC**) simpelweg gekoppeld aan jullie bestaande Microsoft Entra ID (Azure AD), on-premise Active Directory of een andere Identity Provider.
- **Single Sign-On (SSO):** Medewerkers loggen in met hun bestaande gemeentelijke e-mailadres en wachtwoord, inclusief de bestaande Multi-Factor Authenticatie (MFA) die jullie al hebben ingericht.

## 2. Het beheer van de laptops (NixOS in plaats van InTune)

Het beheren van DAWO-laptops vereist een andere denkwijze, maar resulteert in veel **minder** handmatig beheer.

- **Declaratief Beheer (Infrastructure as Code):** Je beheert deze laptops niet door achteraf scripts (via InTune of SCCM) over het netwerk te pushen en te hopen dat ze succesvol installeren. In plaats daarvan beschrijf je de *gewenste eindstaat* in een centraal configuratiebestand. 
- **De 'Fleet Tooling' (DAWO-Sextant):** Laptops halen hun definitie op en bouwen zichzelf exact om naar die beschreven staat. Is een laptop corrupt? Geen urenlange troubleshooting meer. Je herstart de laptop of formatteert hem; binnen enkele minuten is hij weer een 100% kloon van de gewenste staat.
- **Geen 'Linux Kennis' op de servicedesk nodig:** Het beheer van de werkplek wordt doorgaans centraal geregeld (bijvoorbeeld in samenwerkingsverbanden of door een landelijke leverancier). De lokale IT-servicedesk hoeft geen Linux-commando's in te typen; zij delen slechts hardware uit.

## 3. Aansluiting op 'Common Ground'

Het hele DAWO / Mijn Bureau ecosysteem is ontworpen op modulaire, open componenten die API-gedreven met elkaar praten. Dit sluit naadloos aan op de VNG Common Ground visie. Jullie zitten niet vast aan één gigantisch SaaS-blok (vendor lock-in), maar kunnen op termijn componenten uitwisselen zonder de hele werkplek te hoeven vervangen.
