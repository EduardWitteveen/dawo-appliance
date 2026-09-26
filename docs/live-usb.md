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
| Laptop | x86-64, 32 GB RAM recommended (16 GB minimum for this version), virtualisation (VT-x / AMD-V) enabled in the firmware |
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
| `guest.txt` | guest status, cloud-init and K3s logs from inside the guest |
| `hardware.txt` | model, firmware, CPU, memory, disks |

Hand the stick (or that folder) back for debugging.

## 4. Firmware settings and booting

1. **Have your BitLocker recovery key at hand** before changing anything:
   changing Secure Boot or the boot order can make Windows ask for it on its
   next start.
2. Enter the firmware setup (Dell: press **F2** at power-on). Turn **Secure
   Boot off** (the image is not signed) and make sure virtualisation is on.
   A work laptop may have a BIOS password set by IT; then you need IT.
3. Insert both sticks, power on and press the one-time boot menu key
   (Dell: **F12**). Choose the boot stick (UEFI).
4. The desktop appears after about a minute; the welcome dialog shows the
   password. The guest and K3s follow within a few minutes (in the test VM:
   desktop after 19 s, guest after 92 s, K3s Ready after 143 s).

Afterwards: power off, remove the sticks, and turn Secure Boot back on.

## How this is tested

`nix build .#test-live-iso-boot` boots this exact image under UEFI from an
emulated USB stick, next to a patterned "internal disk" and a `DAWO_LOGS`
stick. It passes only when the desktop, the guest and K3s report ready, the
report reaches the log stick, and the internal disk is byte-for-byte
unchanged (`docs/testing.md`, R29).
