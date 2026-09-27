# Live USB: try the appliance on your own laptop

> Experimental and unofficial. Not for production. See `README.md`.

The live USB boots an existing machine into the DAWO appliance without
installing anything: the machine's own disk is never written (ADR 0006,
issue #93). Power off and remove the stick, and the machine is as it was.

**What this first version shows:** the DAWO workplace (Plasma desktop, logged
in automatically as `dawo`), the Ubuntu 24.04 guest VM and single-node K3s in
that guest. **Mijn Bureau is not in it yet**: that needs a data partition on
the stick and the laptop profile (next slices of #93). Everything runs in
RAM, so nothing survives a reboot.

## What you need

| Item | Requirement |
|---|---|
| Laptop | x86-64 with virtualisation (VT-x / AMD-V) enabled in the firmware. The desktop runs on 8 GB; the guest needs at least 9 GB in total (6 GB stays for the desktop, 3 GB minimum for the guest); 16–32 GB recommended |
| Boot stick | USB 3, at least 16 GB (the image is about 6.5 GB). Everything on it is erased |
| Log stick (optional, recommended) | Any USB stick, formatted FAT32 or exFAT with the name `DAWO_LOGS`. Files on it are kept |

## 1. Build the image

In a WSL shell (`wsl -d Ubuntu-24.04`; the prompt ends in `$`):

```bash
cd /mnt/c/git/dawo-appliance
nix build .#appliance-live-iso -o ~/live-iso
ls -la ~/live-iso/iso/
```

You see one file, `dawo-appliance-live.iso`. To copy it to Windows:

```bash
cp ~/live-iso/iso/dawo-appliance-live.iso /mnt/c/Users/$USER/Downloads/
```

## 2. Write the boot stick

On Windows, use [Rufus](https://rufus.ie): select the stick, select the ISO,
and choose **"DD image"** mode when Rufus asks. Double-check the selected
drive: Rufus erases it.

## Internet: the demo Wi-Fi "Dawo"

Every live boot starts without a known network. The image therefore knows
one demo network: make a Wi-Fi hotspot (for example on your phone) named
**`Dawo`** with password **`DawoDawo`** and security **WPA2** (older laptops
may not support WPA3-only), and the laptop connects by itself. Any network
you choose yourself takes precedence. This password is public (it is in this
repository); use it for demos only (`docs/deviations.md` D27). A network
cable works too.

## The guest adapts to the machine

The stick runs on whatever laptop it is plugged into, so the guest is sized
at boot (`appliance.guest.fitToHost`): at most 8 GB and 6 vCPUs, never more
than the RAM left after 6 GB for the desktop, and one vCPU less than the
machine has. When there is no `/dev/kvm` (virtualisation off in the
firmware, or the machine is itself a VM that does not pass it through, such
as VirtualBox on a Windows host with Hyper-V/WSL2) or less than 3 GB would be
left, the guest is **not started**: the report says why
(`DAWO-LIVE: guest skipped: ...`) and a dialog explains it at login. The
desktop keeps working.

## Debug mode (default for now)

The first boot menu entry, **"DAWO appliance live — … — DEBUG (default for
now): logs + screenshots to USB"**, is the default while the appliance is not
yet stable. It shows a dialog at login saying so, and takes a desktop
screenshot every 30 seconds. With a `DAWO_LOGS` stick present, the
screenshots and the logs are written to it, so the developers (including
Claude, the project's AI assistant) can see afterwards what happened, and so
the screenshots can feed the documentation. **Not for real use:** anything on
screen, passwords included, ends up on the stick. The second entry,
**"… — without debug screenshots"**, takes no screenshots; the text logs still
go to a `DAWO_LOGS` stick when one is present.

Every boot gets its own folder, so repeated boots can be compared.

## 3. Prepare the log stick (for debugging)

In Windows Explorer, right-click the second stick, choose *Format*, file
system FAT32 or exFAT, volume label `DAWO_LOGS`. The appliance only writes
files into that existing filesystem; it never partitions or formats anything
itself.

Every 30 seconds, and once more at shutdown, it writes to
`DAWO_LOGS\dawo-appliance\<boot time>_<id>\`:

| File | Contents |
|---|---|
| `progress.txt` | each stage (desktop, guest, K3s) with seconds since boot |
| `journal.txt` | the full system log of that boot |
| `guest.txt` | guest status, the guest's serial console, cloud-init and K3s logs |
| `hardware.txt` | model, firmware, CPU, memory, disks |
| `health.log` | the desktop health check and dashboard opener log |
| `network.txt` | Wi-Fi/network connections, addresses, DNS, and whether flathub is reachable |
| `screens/` | debug mode: a desktop screenshot every 30 seconds |

Hand the stick (or that folder) back for debugging.

## 4. Firmware settings and booting

1. **Have your BitLocker recovery key at hand** before changing anything:
   changing Secure Boot or the boot order can make Windows ask for it on its
   next start.
2. Enter the firmware setup (Dell: press **F2** at power-on; Toshiba /
   Dynabook: **F2**). Turn **Secure Boot off** (the image is not signed) and
   make sure virtualisation is on. On newer Dells the Secure Boot setting is
   only visible after switching the setup to its **Advanced** / expert view.
   A work laptop may have a BIOS password set by IT; then you need IT.
3. Insert the stick, power on and press the one-time boot menu key (Dell and
   Toshiba / Dynabook: **F12**). Choose the stick under UEFI. From a running
   Windows you can also use *Settings → System → Recovery → Advanced startup
   → Use a device*.
4. The one status window appears at login: login details, internet, virtual
   machine, Mijn Bureau and debug mode. Measured on real hardware
   (2026-09-27): a Dell Latitude 5550 (32 GB) showed the desktop after 20 s,
   the guest after 30 s and K3s Ready after 48 s, and joined the demo Wi-Fi
   by itself; a Dynabook Satellite Pro L50-G (8 GB) showed the desktop after
   21 s and skipped the guest for lack of memory, as designed.
5. **Take the stick out before you start Windows again.** Windows booting
   with the stick inserted can end in its recovery screen (#104); remove the
   stick and restart, nothing on the internal disk is changed.

Afterwards: power off, remove the sticks, and turn Secure Boot back on.

## How this is tested

`nix build .#test-live-iso-boot` boots this exact image under UEFI from an
emulated USB stick, next to a patterned "internal disk" and a `DAWO_LOGS`
stick. It passes only when the desktop, the guest and K3s report ready, the
report reaches the log stick, and the internal disk is byte-for-byte
unchanged (`docs/testing.md`, R29).

## Testing in VirtualBox

A VirtualBox VM (UEFI, the ISO as DVD, a small virtual disk formatted FAT32
`DAWO_LOGS` attached to a **USB** storage controller) runs the desktop, the
report, the logs and the screenshots. On a Windows host with Hyper-V active
(WSL2), VirtualBox cannot pass hardware virtualisation through, so the guest
is skipped there by design. Use bare metal or the KVM test for the guest.

Never use Windows Disk Management on the live stick: Windows ignores the
image's partition entry and may create a partition over the image (#97).
