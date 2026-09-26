# ADR 0006: Live USB first, installing is optional

- Status: Proposed (2026-09-26; maintainer chose the direction "live first, install if you want", details below await review)
- Date: 2026-09-26
- Deciders: maintainer (eywitteveen)
- Amends: ADR 0001 (decision 1, "online install") and ADR 0002 (the ISO is an installer)

## Context

ADR 0001 describes a "bootable installer ISO" that installs a NixOS host onto
a disk. Everything so far follows that: disko, the `--target-disk` +
`--confirm-destroy` guard, and the end-to-end install test (R23).

The maintainer's intent was different, and that was not caught early:
**boot an existing machine from a USB stick and run the appliance, the way an
Ubuntu live CD runs, without touching the machine's own disk.** The target
audience (municipal advisors, CISOs) borrows a laptop that already has
Windows on its only disk. Wiping that disk is not acceptable for a demo.

The first real Mijn Bureau run (#8) also showed that this project needs a way
to **run a check on every boot and get the output back**, including when
something fails. A live medium with a writable data partition gives exactly
that.

Constraints measured or documented so far:

- Mijn Bureau needs a guest with about 16 GiB RAM (laptop profile,
  `docs/upstream/mijn-bureau-sizing.md`), plus 15–20 GB of images and
  databases. That does not fit in RAM next to the guest on a 32 GB machine,
  so a pure RAM-only live system is not possible.
- K3s' datastore and the application databases are sensitive to slow storage.
  A cheap USB 2/3 flash stick is too slow; a USB SSD is not.

## Decision (proposed)

1. **The default medium is a live USB with two partitions**, written once
   from a single image:
   - a boot partition with the appliance system: the same NixOS
     configuration as the installed appliance (DAWO workplace, libvirt, guest,
     health check), with its Nix store as a read-only squashfs;
   - a **data partition** (ext4, label `DAWO_DATA`) mounted at boot for
     everything that must persist or grow: `/var/lib/libvirt` (guest disk),
     `/var/lib/dawo-appliance` (keys, CA, generated password), `/home/dawo`,
     and the logs below. The first boot creates or grows the partition to
     fill the stick; it never looks at any other disk.
2. **The machine's internal disk is never written.** The live system does not
   mount internal disks read-write and does not run disko. This is stronger
   than today's guard, not a replacement for it.
3. **Every boot writes a report to the data partition**, under
   `DAWO_DATA/reports/<timestamp>/`: boot and stage timings, the health-check
   result, `dawo-verify`, the guest and K3s status, and the relevant journal
   excerpts. The partition is also readable from another machine, so a failed
   run can be inspected by plugging the stick in elsewhere. (Windows cannot
   read ext4 natively; a small FAT/exFAT `DAWO_REPORTS` partition may carry a
   copy. To decide during implementation.)
4. **Installing stays available, as an option.** The existing
   `dawo-appliance-bootstrap install --target-disk ... --confirm-destroy`
   remains on the live system for people who want the appliance on a
   dedicated disk. Its tests (R23) stay.
5. **Hardware guidance:** a USB 3 SSD (or a fast USB 3.2 stick) of at least
   128 GB; a machine with 32 GB RAM, 12 threads and VT-x/AMD-V enabled; USB
   boot allowed in the firmware (municipal laptops may lock this behind a
   BIOS password).

## Consequences

- **What stays:** the workplace configuration and its parity (ADR 0003), the
  guest VM, K3s air-gap install, the CA, the health check and all boot and
  guest tests. Both media run the same system.
- **What is new:** an image build for the two-partition stick, the data
  partition mount and first-boot growth, the per-boot report, and a boot test
  that proves the internal disk stays untouched and that data survives a
  reboot.
- **Parity:** DAWO pilot laptops are installed, not live. Running from USB is
  a deviation in how the workplace boots, not in what it is. It gets a row in
  `docs/deviations.md`.
- **Performance:** on a USB SSD the difference with an installed system is
  small. The first boot is slow either way (guest image, K3s, Mijn Bureau
  deploy); later boots reuse the data partition.
- **Updates:** a live stick is updated by writing a new image. The data
  partition must survive that, or be recreated deliberately.
- **Scope:** ADR 0001's "online install" becomes "online live boot, optional
  install". Offline operation stays out of scope.

## Alternatives considered

- **Keep installer-only (status quo).** Rejected by the maintainer: it wipes
  the only disk of the machines the audience actually has.
- **RAM-only live system (like a plain live CD).** Not viable: the guest's
  memory plus its images and databases exceed the RAM of a 32 GB laptop, and
  nothing survives a reboot, so every start would redeploy Mijn Bureau.
- **Install onto an external USB disk with the existing installer.** Works
  today and is not destructive for the internal disk, but it needs a second
  medium and still reads as "installing". It remains possible as a variant
  of decision 4.
