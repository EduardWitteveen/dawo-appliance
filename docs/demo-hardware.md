# Handleiding: Test-hardware en laptop voorbereiding

> Experimenteel en onofficieel. Dit is geen officiële distributie van DAWO, Mijn Bureau of BZK. Voordeur: [`../README.md`](../README.md).

Deze gids helpt gemeentelijke IT-beheerders, werkplek-engineers en technisch adviseurs om een fysieke test-laptop (bijvoorbeeld uit de overgebleven IT-voorraad) klaar te maken voor een live demonstratie van de `dawo-appliance`.

---

## 1. Geschikte laptops & hardware-profielen

Gemeenten hebben vaak afgeschreven, 'einde-lease' of reserve-laptops beschikbaar die uitstekend dienst kunnen doen als demonstratie-unit.

| Profiel | Minimale specificaties | Wat kun je hiermee testen? | Referentie |
| --- | --- | --- | --- |
| **Inspectie & plan** | >= 4 CPU cores, >= 8–16 GiB RAM, x86-64, SSD | Opstarten vanaf de USB, netwerkcontrole, `bootstrap plan` (dry-run zonder schijf-overschrijving) | Slice 1 |
| **Alleen de werkplek (Host)** | >= 4 CPU cores, 16 GiB RAM, >= 32 GiB SSD | De geïnstalleerde DAWO werkplek (KDE Plasma 6 met de pilot-applicaties) | Slice 3 (`appliance-vm`) |
| **Volledige stack demonstratie (`laptop-demo`)** | **>= 8–12 vCPU threads, 32 GiB RAM, >= 64 GiB NVMe/SSD** | Volledige stack: Host werkplek + KVM Ubuntu VM (8 vCPU / 16 GiB) + K3s node + Mijn Bureau kernapplicaties | [`docs/upstream/mijn-bureau-sizing.md`](upstream/mijn-bureau-sizing.md) |

### Veelgebruikte gemeentelijke laptops

Typische modellen die we vaak tegenkomen in de IT-pools van Nederlandse gemeenten en die voldoen aan de aanbevolen 32 GiB specificatie:
- **Dell Latitude** 5400 / 5500 series (bijv. 5420, 5430, 5540, 5550)
- **Lenovo ThinkPad** T-serie of L-serie (bijv. T14 Gen 2/3/4, L14/L15)
- **HP EliteBook** 800-serie (bijv. 840 / 850 G7/G8/G9)

> **RAM Notitie:** Waar de officiële 'single-node' handleiding van Mijn Bureau minimaal 48 GiB RAM vraagt, past dit geoptimaliseerde `laptop-demo` profiel precies op een **32 GiB** referentie-laptop. We draaien hiervoor alleen de kernapplicaties (Keycloak, Bureaublad, Nextcloud, Collabora, Element/Synapse) op het `micro` resource-niveau.

---

## 2. BIOS / UEFI Instellingen

Voordat je de USB-stick start, moet je de firmware van de laptop induiken (meestal F2, F12, of Enter/F1 tijdens het aanzetten) en het volgende configureren:

1. **Virtualisatie (VT-x / AMD-V):**
   - **Verplicht AAN.** De appliance draait de Ubuntu VM lokaal via KVM op de NixOS host. Hardware-virtualisatie is een harde eis.
2. **Boot modus:**
   - **Alleen UEFI** (zet legacy CSM/BIOS boot UIT).
3. **Secure Boot:**
   - **Tijdelijk UIT** voor v0.1 (volgens ADR 0003; integratie van Secure Boot volgt in een latere fase, zie issue #23).
4. **Opslag-controller (Storage):**
   - **AHCI / NVMe.** Als de laptop op "RAID On" of "Intel RST" staat, zet dit dan om naar standaard AHCI, anders herkent Linux de interne schijf niet.

---

## 3. De opstartbare USB-stick maken

Download `dawo-appliance-installer.iso` uit de GitHub Release (of bouw deze lokaal via `nix build .#installer-iso`). Schrijf dit image naar een USB-stick van minimaal 4 GB.

### Optie A: Ventoy (Aanbevolen voor IT-beheerders)
Ventoy is dé standaard tool in veel gemeentelijke IT-afdelingen:
1. Installeer Ventoy op de USB-stick (<https://www.ventoy.net>).
2. Kopieer `dawo-appliance-installer.iso` als een los bestand naar de Ventoy-partitie.
3. Start de laptop op vanaf de USB en kies de ISO in het Ventoy-menu.

### Optie B: Rufus (Windows)
1. Selecteer de USB-stick en de `dawo-appliance-installer.iso`.
2. Partitie-indeling: **GPT**.
3. Doelsysteem: **UEFI (non CSM)**.
4. Kies tijdens het schrijven voor **DD Image mode** (of standaard ISO-modus bij hybrid).

### Optie C: `dd` (Linux / macOS)
```bash
sudo dd if=dawo-appliance-installer.iso of=/dev/sdX bs=4M status=progress conv=fsync
```
*(Vervang `/dev/sdX` met de schijfletter van je USB-stick).*

---

## 4. Veilig opstarten & installatie walkthrough

Het installatieprogramma is ontworpen om fouten te voorkomen: **opstarten vanaf de USB-stick zal nóóit uit zichzelf de harde schijf overschrijven.**

### Stap 1: Veilige inspectie (Dry-run 'plan')
1. Plaats de USB-stick en start de laptop (vaak via F12 op Dell/Lenovo of F9 op HP voor het bootmenu).
2. De live NixOS-omgeving start op met een root shell en actieve netwerkverbinding.
3. Test de hardware-herkenning en manifest-verificatie zónder iets weg te gooien:
   ```bash
   dawo-appliance-bootstrap plan
   ```
4. De tool haalt het vastgezette (`pinned`) manifest op, controleert de SHA-256 handtekening, en laat een voorbeeld zien van de 12 installatie-stappen. De output eindigt netjes met:
   `NO DISK WRITES PERFORMED. This is a plan only (v0.1).`

### Stap 2: Definitieve installatie (Target disk)
Zodra je zeker weet dat dit een afgeschreven test-laptop is en de interne schijf volledig gewist mag worden:

1. Zoek de bestandsnaam van de interne schijf op (bijv. `/dev/nvme0n1` of `/dev/sda`):
   ```bash
   lsblk
   ```
2. Start de installatie. Je móét expliciet de schijf opgeven én het commando bevestigen om per ongeluk wissen te voorkomen:
   ```bash
   dawo-appliance-bootstrap install --target-disk /dev/nvme0n1 --confirm-destroy
   ```
3. De installer formatteert de schijf (Btrfs root + swap), installeert het NixOS besturingssysteem met het DAWO-profiel, maakt het lokale SSL-certificaat (appliance CA) aan, en zet de initiële wachtwoorden klaar.
4. Verwijder na de reboot de USB-stick. Het systeem start nu direct door naar de DAWO KDE Plasma 6 desktop, start de Mijn Bureau VM op de achtergrond, en zet de demonstratieomgeving klaar.

---

## 5. Tips voor bestuurlijke demonstraties

- **Show, don't tell:** Sluit de laptop via HDMI of USB-C aan op een beeldscherm in de vergaderzaal of bestuurskamer. Het systeem configureert externe schermen automatisch.
- **Werkt volledig lokaal (Offline-resilience):** Omdat de héle architectuur (NixOS, Ubuntu, K3s en Mijn Bureau) op deze ene laptop draait met een lokaal netwerk (`*.dawo.internal`), blijft de volledige demo perfect werken, zélfs als de wifiverbinding in de raadszaal even wegvalt.
