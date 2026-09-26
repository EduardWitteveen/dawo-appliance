# BIO-Compliance & Veiligheidsvisie

*Voor de CISO / Security Officer*

De `dawo-appliance` is een v0.1 demonstrator, ontworpen om aan te tonen *dat* een lokaal, soeverein ecosysteem werkt. Om de installatie tijdens demonstraties snel en probleemloos te laten verlopen, zijn er bewust enkele veiligheidsmechanismen tijdelijk uitgeschakeld. 

Voor een CISO is het cruciaal om het verschil te begrijpen tussen deze demonstrator en het uiteindelijke **DAWO productie-ecosysteem**. In productie lost DAWO namelijk de zwaarste BIO-uitdagingen (Baseline Informatiebeveiliging Overheid) rondom cloud-data op.

## De Productie-architectuur (Waarom dit veiliger is dan de cloud)

Wanneer gemeenten overstappen op de officiële DAWO-omgeving (buiten deze demonstrator om), wordt deze uitgerold met zware, verplichte veiligheidsstandaarden:

1. **Volledige Schijfversleuteling (LUKS & TPM 2.0)**
   - Waar deze demonstrator onversleuteld wegschrijft voor het gemak, is de productie-versie onlosmakelijk verbonden met LUKS encryptie. De sleutels worden veilig opgeslagen in de TPM 2.0 module van de laptop. Bij verlies of diefstal is de data cryptografisch onleesbaar.
2. **Datasoevereiniteit (BIO)**
   - Omdat 'Mijn Bureau' (bestanden, chat, documenten) op gecontroleerde overheidsservers draait in plaats van in een Amerikaanse public cloud, voorkom je classificatie-conflicten (zoals rondom de Patriot Act / CLOUD Act). Gevoelige burgerdata verlaat nooit de landsgrenzen of de controle van de overheid.
3. **Reproduceerbare en Controleerbare Code (NixOS)**
   - Traditionele systemen 'roesten' na verloop van tijd door handmatige aanpassingen (configuratie drift). Omdat DAWO is gebaseerd op NixOS, is elke laptop wiskundig bewijsbaar identiek aan de goedgekeurde broncode. Een hacker kan niet zomaar een systeemdienst aanpassen op de achtergrond, want bij de volgende opstart herstelt het systeem zich naar de read-only 'gewenste staat'.

## Welke concessies doet deze specifieke v0.1 demonstrator?

Als je deze appliance installeert op een test-laptop, houd dan rekening met de volgende (tijdelijke) afwijkingen ten opzichte van productie:

- **Geen Encryptie (LUKS is uit):** Het bestandssysteem is direct leesbaar. Zet hier geen echte, gevoelige gemeentelijke data op.
- **Tijdelijke Certificaten (Self-signed):** Omdat deze laptop geen openbare domeinnaam heeft, genereert hij tijdens de installatie zijn eigen SSL-certificaten. Dit is cryptografisch veilig voor de demonstratie, maar in productie gebruik je uiteraard PKIoverheid of Let's Encrypt.
- **Wachtwoorden in beeld:** Voor het gemak van de presentator toont de demonstrator het test-wachtwoord op het inlogscherm. In productie gebeurt dit uiteraard nooit.

**Conclusie voor de CISO:** Deze appliance bewijst de *functionaliteit* van de onafhankelijke werkplek. Het fundamentele veiligheidsmodel erachter (DAWO-Core) behoort tot de meest geharde, auditeerbare besturingssystemen die momenteel beschikbaar zijn.
