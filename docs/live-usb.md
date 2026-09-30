# Live USB: try the appliance on your own laptop

> Experimental and unofficial. Not for production. See `README.md`.

The live USB boots an existing machine into the DAWO appliance without
installing anything: the machine's own disk is never written (ADR 0006,
issue #93). Power off and remove the stick, and the machine is as it was.

**What it shows:** the DAWO workplace (Plasma desktop, logged in
automatically as `dawo`), the Ubuntu 24.04 guest VM with single-node K3s, and
Mijn Bureau in the laptop profile (ADR 0007: Keycloak, Bureaublad, Nextcloud,
Collabora, Element), which deploys itself once K3s and internet are up. A
status page opens at login and shows the progress. On the Dell Latitude 5550
(2026-09-30, USB SSD): desktop in about 20 s, K3s in about 50 s, Mijn Bureau
in about 8 minutes once its images are on the stick; login as `dawo` /
`dawo` reaches the Bureaublad dashboard, Nextcloud and Element.

With a `DAWO_LOGS` partition that has room, the guest disk and the appliance's
keys are kept on the stick and reused on the next boot ("Data that survives a
reboot" below). The desktop itself, including the home folder, runs in RAM and
starts clean every time.

## What you need

| Item | Requirement |
|---|---|
| Laptop | x86-64 with virtualisation (VT-x / AMD-V) enabled in the firmware. The desktop runs on 8 GB; the guest needs at least 9 GB in total (6 GB stays for the desktop, 3 GB minimum for the guest); 16–32 GB recommended |
| Boot medium | **A USB SSD of 64 GB or more** (an SSD in a USB enclosure, or a portable one such as a Samsung T7). A USB flash stick of 16 GB boots the desktop, but keeping the guest on it means hours of writes (a Mijn Bureau deployment grows the guest disk to about 13 GB): a SanDisk stick died after two days of this and ran hot (#139). The image takes about 7 GB; the rest becomes the `DAWO_LOGS` partition for logs, screenshots and data ("Writing the stick" below). Everything on it is erased the first time; up to 2 TB (MBR). `io.txt` in each session's logs records how many GB the session wrote (#147) |
| Second stick (optional) | Only when `DAWO_LOGS` is not on the boot stick: any USB stick formatted FAT32 or exFAT with the name `DAWO_LOGS`. Files on it are kept |

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

## 2. Writing the stick

The stick holds two things: the image at the start, and after it a partition
`DAWO_LOGS` (exFAT) for the logs, the screenshots and the data that survives a
reboot. Writing a newer image later keeps `DAWO_LOGS` and its files. Two
tools do this, with the same result (#97):

- Windows: `scripts\windows\dawo-stick.ps1`
- Linux: `scripts/write-live-stick.sh`

Both only show what they would do (`plan`) unless you add the confirmation
flag, and both refuse a disk that is not USB or is too small. The layout: the
ISO as is from byte 0; partition entry 3 of the MBR, type 0x07, starting 1 MiB
after the end of the image (rounded up to a whole MiB), up to the end of the
stick. Afterwards the tool checks the image area byte for byte against the
ISO.

**Never use Windows Disk Management (or `New-Partition`, or a "format this
drive" prompt) on this stick.** Windows ignores the image's own partition
entry and may create a partition over the image, which breaks it. If Windows
offers to format a drive on the stick, choose *Cancel*. Windows does not show
`DAWO_LOGS` at all; use the tool's `read` action to get the logs.

### On Windows

Open an **Administrator PowerShell window**: Start menu, type `PowerShell`,
right-click *Windows PowerShell*, *Run as administrator*. The window title
starts with *Administrator*. Type the commands there:

```powershell
cd C:\git\dawo-appliance
Get-Disk        # find the stick: BusType USB, the right size; note its Number
powershell -ExecutionPolicy Bypass -File .\scripts\windows\dawo-stick.ps1 -DiskNumber 2
```

(`2` is an example: use the stick's number.) This is `plan`: it shows the
disk, its partition entries, whether `DAWO_LOGS` is there and what `write` and
`create` would do. It writes nothing. The ISO is taken from
`Downloads\dawo-appliance-live.iso` (`-Iso <path>` for another one); when a
`dawo-appliance-live.iso.sha256` file lies next to it, the ISO is checked
against it first.

**A new stick (or one without `DAWO_LOGS`): `create`.** Windows cannot format
the partition, so its exFAT metadata is made in WSL first. `plan` prints the
exact command with the partition size in bytes; in a WSL shell
(`wsl -d Ubuntu-24.04`, the prompt ends in `$`):

```bash
cd /mnt/c/git/dawo-appliance
nix develop -c bash scripts/make-dawo-logs-head.sh <size-from-plan> /mnt/c/Users/$USER/Downloads/dawo-logs-head.bin
```

Then, back in the Administrator PowerShell window:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\dawo-stick.ps1 -Action create -DiskNumber 2 -ExfatHead $env:USERPROFILE\Downloads\dawo-logs-head.bin -ConfirmDestroy
```

This erases the whole stick, `DAWO_LOGS` included.

**A newer image on a stick that has `DAWO_LOGS`: `write`.** The logs and data
stay:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\dawo-stick.ps1 -Action write -DiskNumber 2 -ConfirmDestroy
```

**Get the logs and screenshots: `read`.** Read-only; copies
`DAWO_LOGS\dawo-appliance\` to `Downloads\dawo-stick-logs\` (`-OutDir <path>`
for another folder). The large data files (`dawo-data.ext4`, `dawo-images\`)
are not copied.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\dawo-stick.ps1 -Action read -DiskNumber 2
```

How it gets past Windows: Windows silently drops raw writes to a region it
treats as a volume. The tool therefore first sets the type of all four MBR
entries to 0x00 (Windows then sees no partitions), writes the image from
4 MiB on (and, for `create`, the exFAT metadata), and writes the first 4 MiB,
with the real partition entries, last.

### On Linux

In a terminal on a Linux machine with the stick plugged in (WSL does not see
USB sticks by default; use the Windows tool there). `create` needs
`mkfs.exfat`: install `exfatprogs`, or use `nix develop` in this repository.

```bash
cd dawo-appliance
lsblk -o NAME,SIZE,TRAN,MODEL      # find the stick: TRAN usb, e.g. /dev/sdb
bash scripts/write-live-stick.sh --target /dev/sdb --iso ~/live-iso/iso/dawo-appliance-live.iso
sudo bash scripts/write-live-stick.sh --action create --target /dev/sdb --iso ~/live-iso/iso/dawo-appliance-live.iso --confirm-destroy
sudo bash scripts/write-live-stick.sh --action write --target /dev/sdb --iso ~/live-iso/iso/dawo-appliance-live.iso --confirm-destroy
```

The first line is `plan` (it may need `sudo` to read the stick), the second
creates the stick with an empty `DAWO_LOGS`, the third writes a newer image
and keeps `DAWO_LOGS`. Inside `nix develop`, use
`sudo env "PATH=$PATH" bash scripts/write-live-stick.sh ...` so that `sudo`
finds `mkfs.exfat`. Unmount the stick first; the tool refuses a mounted one.
Linux reads `DAWO_LOGS` like any exFAT stick, so no `read` action is needed.

Both tools also accept a disk image file instead of a disk (`-ImagePath` /
`--target <file>`), which is how `tests/test-live-stick-tool.sh` tests them.

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

## Data that survives a reboot

With a `DAWO_LOGS` partition (on the boot stick) or stick that has at least
12 GB free, the appliance keeps its
data there: a small file `dawo-data.ext4` (1 GB: the guest's SSH key, the
appliance CA, the cloud-init seed) and a folder `dawo-images/` with the
guest disk, which grows only as the guest writes to it. Later boots reuse
both, so the guest starts faster and nothing is set up again (#109, #113).
The status window shows "Opslag: op de USB-stick". Without such a stick, or
with too little room, everything stays in RAM and is gone after power-off, as
before. Nothing is ever partitioned or formatted: only files are created
inside the `DAWO_LOGS` filesystem you prepared (section 2).

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

## 3. The logs on `DAWO_LOGS` (for debugging)

`DAWO_LOGS` is normally the partition on the boot stick (section 2). Without
it, a second stick works too: in Windows Explorer, right-click that stick,
choose *Format*, file system FAT32 or exFAT, volume label `DAWO_LOGS` (only
for that second stick, never for the boot stick). The appliance only writes
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
| `health.log` | the dashboard opener's health log; absent on the live USB, which opens Mijn Bureau from the status page instead (#159) |
| `network.txt` | Wi-Fi/network connections, addresses, DNS, and whether flathub is reachable |
| `screens/` | debug mode: a desktop screenshot every 30 seconds |

Hand the stick (or that folder) back for debugging. On Windows, copy the
folder off the boot stick with `dawo-stick.ps1 -Action read` (section 2).

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

### Per model (tested by the maintainer, 2026-09-27)

| Machine | Firmware setup | Secure Boot off | Boot the stick |
|---|---|---|---|
| **Dell Latitude 5550** (current Dell BIOS UI) | power on, tap **F2** | Switch the setup to its **Advanced** view first (without it the change was refused: *"The changes to the Secure Boot configuration were not accepted"* and the old setting came back). Then **Boot Configuration → Secure Boot**: the blue toggle at the top, under *"For Secure Boot to be enabled…"*, from **ON** to **OFF** (not *Enable Microsoft UEFI CA*). **Apply Changes**, confirm, **Exit**. No admin password was needed | tap **F12** at the Dell logo → *One-Time Boot Menu* → the USB stick under **UEFI** |
| **Toshiba / Dynabook Satellite Pro L50-G** | power on, hold **F2** | **Security → Secure Boot → Disabled**, **F10** to save. Without it: *"EFI USB device has been blocked by the current security policy"* | hold **F12** at power on → the USB stick |

Windows asks for the BitLocker recovery key after a Secure Boot change only
when BitLocker is on; check with `manage-bde -status C:` in an administrator
command prompt (the maintainer's Dell: *Protection Off*).

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
image's partition entry and may create a partition over the image (#97). Use
the tools in section 2.
