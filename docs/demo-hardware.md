# Demo hardware and laptop setup guide

> Experimental and unofficial. Not an official DAWO, Mijn Bureau or BZK
> distribution. Front door: [`../README.md`](../README.md).

This guide helps municipal IT administrators, workplace engineers, and technical
advisors prepare a physical test laptop or desktop from existing organizational
inventory to demonstrate `dawo-appliance` live on real hardware.

---

## 1. Candidate machines & hardware profiles

Municipal organizations frequently have decommissioned, lease-returned, or spare
laptops available that make excellent demonstration units.

| Profile | Target machine specs | What runs | Sizing reference |
| --- | --- | --- | --- |
| **Inspection & plan** | >= 4 CPU cores, >= 8–16 GiB RAM, x86-64, SSD | Live ISO boots, network verification, `bootstrap plan` (dry-run) | Slice 1 |
| **Host desktop only** | >= 4 CPU cores, 16 GiB RAM, >= 32 GiB SSD | Installed DAWO workplace (KDE Plasma 6, pilot app set) | Slice 3 (`appliance-vm`) |
| **Full stack demo (`laptop-demo`)** | **>= 8–12 vCPU threads, 32 GiB RAM, >= 64 GiB NVMe/SSD** | Full stack: Host desktop + KVM Ubuntu VM (8 vCPU / 16 GiB) + single-node K3s + Mijn Bureau core apps | [`docs/upstream/mijn-bureau-sizing.md`](upstream/mijn-bureau-sizing.md) |

### Common municipal laptop models

Typical models commonly found in Dutch municipal hardware pools that meet the
recommended 32 GiB demo profile:
- **Dell Latitude** 5400 / 5500 series (e.g. 5420, 5430, 5540, 5550)
- **Lenovo ThinkPad** T-series or L-series (e.g. T14 Gen 2/3/4, L14/L15)
- **HP EliteBook** 800 series (e.g. 840 / 850 G7/G8/G9)

> **RAM Note:** While upstream Mijn Bureau's standard single-node guide asks for
> 48 GiB RAM, the optimized `laptop-demo` profile fits onto a **32 GiB**
> reference laptop by running core applications (Keycloak, Bureaublad, Nextcloud,
> Collabora, Element/Synapse) with the `micro` resource preset
> ([`docs/upstream/mijn-bureau-sizing.md`](upstream/mijn-bureau-sizing.md)).

---

## 2. BIOS / UEFI settings

Before booting the installer, enter the machine's firmware setup (typically F2,
F12, or Enter/F1 during power-on) and configure the following:

1. **Virtualization technology (VT-x / AMD-V):**
   - **Must be Enabled.** The appliance runs the Ubuntu 24.04 guest VM inside
     KVM on the NixOS host. Hardware-assisted virtualization is strictly required.
2. **Boot mode:**
   - **UEFI only** (disable legacy CSM/BIOS boot).
3. **Secure Boot:**
   - **Disabled** for v0.1 (per ADR 0003; Secure Boot integration is documented
     for post-MVP hardening in issue #23).
4. **Storage controller mode:**
   - **AHCI / NVMe.** If the controller is set to "RAID On" or "Intel RST", switch
     to standard AHCI mode so Linux kernel drivers can address the disk directly.

---

## 3. Creating the bootable USB flash drive

Download `dawo-appliance-installer.iso` from the release artifacts (or build it
locally via `nix build .#installer-iso`). Write the image to a USB flash drive
(minimum 4 GB):

### Option A: Ventoy (Recommended)
Ventoy is the easiest standard tool for municipal admins:
1. Install Ventoy onto a USB drive (<https://www.ventoy.net>).
2. Copy `dawo-appliance-installer.iso` directly onto the Ventoy partition.
3. Boot the laptop from USB and select the ISO from the Ventoy menu.

### Option B: Rufus (Windows)
1. Select the USB drive and the `dawo-appliance-installer.iso`.
2. Partition scheme: **GPT**.
3. Target system: **UEFI (non CSM)**.
4. When prompted, write in **DD Image mode** (or standard ISO mode if hybrid).

### Option C: `dd` (Linux / macOS)
```bash
sudo dd if=dawo-appliance-installer.iso of=/dev/sdX bs=4M status=progress conv=fsync
```
*(Replace `/dev/sdX` with the actual block device of your USB drive, not a partition).*

---

## 4. Booting & safe verification walkthrough

The installer is designed with safety defaults: **booting the live medium will
never write to the laptop's internal disk automatically.**

### Step 1: Safe inspection (`plan`)
1. Insert the USB drive and boot the laptop (press F12 on Dell/Lenovo or F9 on HP
   for the boot menu).
2. The live NixOS environment boots into a root shell with active networking.
3. Test hardware detection and manifest verification without writing anything:
   ```bash
   dawo-appliance-bootstrap plan
   ```
4. The tool downloads the pinned manifest, checks its SHA-256 signature, and
   previews the twelve installation steps. Output concludes with:
   `NO DISK WRITES PERFORMED. This is a plan only (v0.1).`

### Step 2: Gated installation (Target disk)
Once you have confirmed that the machine is a dedicated test unit whose internal
storage may be wiped:

1. Identify the target disk device path (e.g. `/dev/nvme0n1` or `/dev/sda`):
   ```bash
   lsblk
   ```
2. Run the gated installer requiring both an explicit disk and confirmation:
   ```bash
   dawo-appliance-bootstrap install --target-disk /dev/nvme0n1 --confirm-destroy
   ```
3. The installer partitions the target disk using Disko (Btrfs root + swap),
   installs the NixOS host configuration with the DAWO desktop profile, creates
   the per-install appliance CA, and stages the initial credentials.
4. Upon reboot, remove the USB drive. The system boots into the DAWO KDE Plasma 6
   desktop, launches the VM in the background, and prepares the workspace demo.

---

## 5. Demonstration tips for meetings

- **Show, don't tell:** Connect the laptop to a meeting room projector or external
  monitor via HDMI or USB-C. Plasma automatically configures standard displays.
- **Offline / Local resilience:** Because the entire appliance stack (NixOS host,
  Ubuntu VM, K3s, and Mijn Bureau) runs self-contained on the machine with a
  local CA (`*.dawo.internal`), the demo continues to work even when disconnected
  from the municipality's Wi-Fi network.
