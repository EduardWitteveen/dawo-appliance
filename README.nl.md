[English](README.md) | [Nederlands](README.nl.md)

# dawo-appliance

> **Experimenteel en niet-officieel.** Dit is een onafhankelijk open-source experiment. Het is **geen** officiële distributie van DAWO, Mijn Bureau of het Ministerie van BZK, en wordt niet door hen ondersteund.

Een reproduceerbare demonstratie-appliance voor een **digitaal autonome overheidswerkplek op één enkele computer**. 

Een compacte opstartbare installer-ISO installeert — pas na een expliciete en bevestigde schijfkeuze — de **DAWO-werkplek** (de op NixOS gebaseerde overheidswerkplek van [DAWO-Core](https://codeberg.org/DAWO/DAWO-Core), exact hetzelfde profiel als een pilot-laptop van de Rijksoverheid) met een lokale Ubuntu 24.04 virtuele machine (KVM/libvirt), single-node K3s, een uitrol van [Mijn Bureau](https://code.overheid.nl/MinBZK/mijn-bureau-infra), een automatische gezondheidscontrole, waarna het Mijn Bureau bureaublad direct in de browser opent.

Waarom dit bestaat, wat het toevoegt en wat het vraagt: [`docs/purpose.md`](docs/purpose.md) (in het Engels).  
Volledige documentatie-index: [`docs/README.md`](docs/README.md).

---

## Hoe het eruit ziet

![De geïnstalleerde werkplek na automatische aanmelding: de DAWO-werkplek (KDE Plasma 6, DAWO-Core 0.1.3) met het welkomstscherm](docs/screenshots/appliance-desktop.png)

*Het geïnstalleerde systeem na inschakelen: automatische aanmelding als `dawo` in de DAWO-werkplek (DAWO-Core 0.1.3, KDE Plasma 6) met het welkomstscherm van de appliance, waarin het inlogwachtwoord wordt getoond met de melding "not for production". Automatisch vastgelegd tijdens de boot-test; het getoonde wachtwoord is een tijdelijk testwachtwoord.*

![De live installer na dawo-appliance-bootstrap plan: gepinde versies, twaalf stappen, niets naar schijf geschreven](docs/screenshots/installer-plan.png)

*De live ISO na het commando `dawo-appliance-bootstrap plan`: alle gepinde versies, de twaalf stappen die uitgevoerd zouden worden, en de garantie "NO DISK WRITES PERFORMED".*

Beide beelden worden automatisch vastgelegd door de geautomatiseerde boot-tests van de gepinde configuratie (in een software-rendered virtuele machine), nooit handmatig bewerkt. Herkomst en richtlijnen: [`docs/screenshots/README.md`](docs/screenshots/README.md).

---

## Waarom dit relevant is voor de publieke sector

Overheden en gemeenten werken actief aan **digitale soevereiniteit**, de reductie van afhankelijkheid van Big Tech (zoals Microsoft 365) en aansluiting bij de VNG Common Ground-principes.

Dit project brengt twee toonaangevende open-source overheidsprojecten samen in één werkende, tastbare demonstratie:
1. **Show, don't tell:** Binnen korte tijd live demonstreren aan collega's, CISO's of bestuurders dat een soevereine werkplek zónder cloud-lockin daadwerkelijk bestaat en direct werkt.
2. **100% Lokaal en veilig:** Geen externe cloudservices nodig; gegevens blijven op het apparaat zelf.
3. **Reproduceerbaar en controleerbaar:** Elke softwarecomponent, versie en container image is vastgepind in [`manifest/appliance-manifest.json`](manifest/appliance-manifest.json). Twee personen die dezelfde release bouwen krijgen exact hetzelfde resultaat.
4. **Standaard veilig en niet-destructief:** De installer start standaard in een veilige inspectiemodus (`plan`). Er wordt pas naar een schijf geschreven na een expliciete schijfkeuze (`--target-disk`) én een expliciete vernietigingsbevestiging (`--confirm-destroy`).

---

## Status van de ontwikkeling

Het project wordt opgebouwd in verticale lagen (*slices*, zie [`docs/roadmap.md`](docs/roadmap.md)), die elk afzonderlijk getest en uitgevoerd kunnen worden. Sessie-overdracht en actuele stand: [`docs/STATUS.md`](docs/STATUS.md).

| Laag (Slice) | Omschrijving | Status |
| --- | --- | --- |
| 0 | Basisstructuur: gepind manifest + controlegetal, Nix flake/dev shell, bootstrap `plan`/`verify` | Gereed |
| 1 | Niet-destructieve live ISO + dry-run bootstrap | Gereed, geverifieerd |
| 2 | Installatie naar schijf (Disko, beveiligd met `--target-disk` + `--confirm-destroy`); geen LUKS in v0.1 | Gereed, geverifieerd |
| 2c | Upstream verversing: DAWO-Core 0.1.3, nixpkgs 26.05, mijn-bureau-infra juli 2026, ADR 0002/0003 | Gereed |
| 3 | DAWO-werkplek (`profiles-dawo-generic`, Plasma) + KVM/libvirt, gelijkheidstoets, `nix run .#appliance-vm` | Gebouwd, boot-test geslaagd; visuele controle open |
| 4a | Ubuntu 24.04 VM: libvirt-netwerk + gastdomein + cloud-init (`hosts/appliance/guest-vm.nix`) | Gekoppeld aan appliance host; boot-test open |
| 4b | Per-installatie appliance CA + browservertrouwen (`hosts/appliance/appliance-ca.nix`) | Gebouwd; boot-test assertions geschreven |
| 5 | Single-node K3s installer, gepind en offline getest (`k8s/bootstrap/install-k3s.sh`) | Verwerkt in cloud-init van de gast-VM |
| 6 | Mijn Bureau deploy driver (Helmfile, gepinde revisie) | Geschreven en offline getest (19 tests) |
| 7 | Gezondheidscontrole + automatisch openen van de browser | Geschreven en offline getest; integratie met autostart open |

**Wat vandaag al werkt:** De `dawo-appliance-installer.iso` start op, activeert het netwerk, downloadt en verifieert het gepinde manifest via SHA-256, toont het installatieplan en installeert de host naar een expliciet bevestigde schijf. Die host is de volledige DAWO-werkplek (SDDM + KDE Plasma 6, het pilot-applicatiepakket, nl_NL-taalinstellingen, verplichte hardening) met KVM/libvirt. De lagen 4–7 (VM, K3s en Mijn Bureau) bevatten werkende code en offline tests, maar moeten nog live end-to-end opgestart worden.

---

## Verificatie en kwaliteitsborging

Eén commando voert alle geautomatiseerde controles uit: `bash scripts/verify.sh`. Het resultaat van de **meest recente echte testrun** is vastgelegd in [`docs/verification-latest.md`](docs/verification-latest.md) (dit bestand wordt uitsluitend door dat script gegenereerd). Wat elke test dekt: [`docs/testing.md`](docs/testing.md).

Een release is pas een officiële release wanneer alle checks in dit rapport op groen staan.

---

## Uitproberen zonder te installeren

De geïnstalleerde host kan lokaal als virtuele QEMU-machine gestart worden (vereist Linux met Nix, KVM, een grafische weergave en circa 6 GiB RAM voor de VM):

```bash
git clone https://github.com/EduardWitteveen/dawo-appliance
cd dawo-appliance
nix run .#appliance-vm
```

Er opent een QEMU-venster; de VM start met het BZK-opstartscherm, meldt automatisch aan als `dawo` en toont het welkomstscherm met inloggegevens. De eerste start downloadt de benodigde pakketten (enkele gigabytes).

---

## Hardware-eisen voor demonstratie

Voor de volledige demonstratiestack (met desktop, Ubuntu VM, K3s en Mijn Bureau) gelden de volgende richtlijnen:

- **Eenvoudige inspectie / ISO-test:** Draait op vrijwel elke moderne x86-64 machine of testlaptop met >= 8–16 GiB RAM.
- **Volledige demonstratiestack (Host + VM + Mijn Bureau):** Mijn Bureau vereist op een single-node Kubernetes cluster aanzienlijke rekenkracht (minimaal 8–12 vCPU en 16–32 GiB RAM voor de gast-VM). Een fysieke demomachine heeft bij voorkeur **>= 8–12 cores en 32–64 GiB RAM**.

---

## Upstream projecten (gebruikt, niet geforkt)

- **DAWO-Core:** <https://codeberg.org/DAWO/DAWO-Core>, gepind op release `0.1.3`.
- **mijn-bureau-infra:** <https://code.overheid.nl/MinBZK/mijn-bureau-infra>, gepind op revisie `b2ae545…`.

Exacte software-pins: [`manifest/appliance-manifest.json`](manifest/appliance-manifest.json) en [`docs/upstream/revisions.md`](docs/upstream/revisions.md).

---

## Mappenstructuur

| Pad | Doel |
| --- | --- |
| `flake.nix`, `flake.lock` | Nix flake: pakketten, tests, boot-tests, dev shell |
| `installer/` | Live installer ISO en het `dawo-appliance-bootstrap` commando |
| `hosts/appliance/` | De geïnstalleerde host: DAWO-werkplek + toevoegingen |
| `hosts/profiles/disko/` | Schijfindeling met expliciete doelschijf |
| `vm/`, `k8s/`, `apps/`, `health/` | Lagen 4–7: VM, K3s, Mijn Bureau en gezondheidscontrole |
| `manifest/` | Gepind release-manifest + SHA-256 controlegetal |
| `scripts/` | Hulpscripts: `status.sh`, `verify.sh`, `speed-check.sh`, `screenshots.sh` |
| `tests/` | Lokale dry-run testsuite (zonder Nix, root of netwerk) |
| `docs/` | Alle documentatie; begin bij [`docs/README.md`](docs/README.md) |
| `AGENTS.md` | Standaard werkwijze en richtlijnen voor AI-agents en bijdragers |

---

## Licentie

**EUPL-1.2** (European Union Public Licence v. 1.2), zie [`LICENSE`](LICENSE).  
Sluit aan bij Mijn Bureau (EUPL-1.2) en is compatibel met DAWO-Core (GPL-3.0). Er worden nooit geheimen of wachtwoorden opgeslagen in Git; deze worden pas lokaal tijdens de installatie gegenereerd ([`docs/architecture.md`](docs/architecture.md)).
