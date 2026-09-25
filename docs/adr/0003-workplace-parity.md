# ADR 0003: The appliance host is the DAWO workplace, unchanged, plus additions

- Status: Accepted
- Date: 2026-09-25
- Deciders: maintainer (eywitteveen)

## Context

The maintainer's requirement is explicit: after installation the appliance must
give **the same user experience, one to one, as a DAWO pilot workplace**. A
"DAWO desktop" that only borrows the KDE Plasma module would not satisfy that.

What a DAWO workplace *is* at the pinned DAWO-Core release 0.1.3
(`docs/upstream/revisions.md`): a pilot client host such as `hosts/dawo-t495s`
imports

- `boot-loader`, `boot-plymouth-bzk`: systemd-boot and the BZK boot splash;
- `disko-single-nvme-luks`: Btrfs on LUKS on `/dev/nvme0n1`;
- `hardware-lenovo-t495s`: the laptop model;
- **`profiles-dawo-generic`**, the composite workplace profile:
  `hardware-dawo-base`; `profiles-dawo-core` (mandatory hardening forced on:
  PAM lockout and password quality, SSH policy, sysctl baseline, time sync);
  `desktop-plasma`, `desktop-gnome`, `desktop-sddm-bzk`, `desktop-select`
  (exactly one desktop must be enabled); environment (variables, packages,
  fonts, version); `apps-sets` (opt-in sets, KeePassXC opt-out);
  `tools-diagnostics`; `localization-nl_nl`; `networking-client`; Nix
  settings; programs (git, zsh, Chromium, Firefox); services (audio,
  auto-update via comin, update status, Flatpak, printing, scanning); users
  (`users-basics`, `users-dawo`, `users-deploy`);
- `maid-dawo-generic`: user-level settings via nix-maid;

and sets `dawo.desktop.plasma.enable = true`, the pilot app set
`dawo.apps.{office,comms,creative,media}.enable = true` (LibreOffice by
default) and `dawo.secureboot.enable = false`.

## Decision

1. **Import the same module set a pilot client imports**: `boot-loader`,
   `boot-plymouth-bzk`, `profiles-dawo-generic`, `maid-dawo-generic`. Set the
   same host-level choices: Plasma, the four pilot app sets, Secure Boot off.
   Never cherry-pick the desktop module alone.
2. **Additions only.** The appliance adds `virtualisation.libvirtd`, the
   Ubuntu VM, K3s and Mijn Bureau services, the health check and the browser
   autostart. It does **not** override upstream options that shape the user
   experience (theme, apps, locale, login policy, hardening, desktop packages).
3. **Every deviation is deliberate and listed here.** Anything not on this list
   is a bug against parity.

   | Deviation | Why | Visible to the user? |
   | --- | --- | --- |
   | Storage: our explicit-target disko module, **no LUKS** in v0.1 | non-destructive-by-default rule; demo, simpler to debug (roadmap Slice 2b) | no passphrase prompt at boot; otherwise identical |
   | Hardware: generic module (`hardware-generic-intel` or `-amd` on top of `hardware-dawo-base`) instead of a laptop model | the appliance is not one laptop model | no (firmware and driver level) |
   | **Auto-update off** (`dawo.autoUpdate.enable = false`) | the appliance is a pinned, reproducible artifact; comin would rebuild the host from Codeberg `main` and drop our additions | the update-status indicator shows "disabled" instead of a poll time |
   | **Auto-login** as `dawo` into Plasma (`services.displayManager.autoLogin`, mkForce over upstream's `false`) | demo appliance: land on the desktop, nothing to type. The screen still locks per upstream's hardening rule; the welcome dialog says which password unlocks it | yes: no SDDM login screen at boot |
   | **Welcome dialog** at Plasma login (XDG autostart, kdialog): what the machine is, who is logged in, which password to use, what is running | the one place a user is told what to type; Slice 7 opens the dashboard from the same hook | yes, as an addition |
   | Bootstrap user `dawo` keeps **upstream's documented default password** by default (`acknowledgeDefaultPassword = true`), exactly as a freshly imaged pilot device. `dawo-appliance-bootstrap install --generate-password` instead ships the yescrypt hash of a random password (`/var/lib/dawo-appliance/dawo.password-hash`) **and its plain text** (`dawo.password.txt`, world-readable) via `disko-install --extra-files`; `dawo-appliance-set-password.service` applies the hash once at first boot and deletes it; the plain text stays so the welcome dialog can show it. **Demo appliance, not for production**: passwords are on screen and on disk by design, and the dialog says so. `users.mutableUsers` stays true, so later `passwd` changes stick as upstream. | as easy as possible for a demo; a random password on request; nothing secret in Git | the password is shown in the welcome dialog after every login, and once at install |
   | Microcode updates enabled for both CPU vendors | generic hardware; upstream picks one per laptop model | no |
   | Desktop fixed to Plasma | pilot default; `desktop-select` demands exactly one | no |
   | Extra software and services (libvirt, VM, browser autostart) | the appliance's purpose | yes, as additions |

4. **Parity check.** `nix flake check` runs `checks.workplace-parity`
   (`nix/parity.nix`): an evaluation-time comparison of the option values that
   define the pilot experience (`dawo.desktop.*`, `dawo.apps.*`, hardening
   switches, display manager, locale, boot loader, ...) between the appliance
   host and upstream's `hosts/dawo-t495s` at the pinned tag. Recorded
   deviations (today only `dawo.autoUpdate.enable`) are asserted to hold on
   both sides; anything else that differs fails the check with a report. A pin
   bump that changes the pilot's choices therefore fails until the appliance
   follows or the deviation is recorded above and in `nix/parity.nix`.
5. **Boot loader follows upstream.** Slice 2's GRUB choice is dropped; the
   appliance uses upstream `boot-loader` (systemd-boot, Secure Boot opt-in and
   off) and `boot-plymouth-bzk`, like the pilot.

## Consequences

- A DAWO-Core pin bump is a **user-experience change**, not just a dependency
  update. `docs/upstream/revisions.md` records what changed for the user.
- The host closure grows (GIMP, Inkscape, Krita, Penpot, Element, VLC,
  LibreOffice, Thunderbird, KDE extras). Acceptable: it is the pilot's set.
- Our existing `users.users.dawo` definition (Slice 2) must be reconciled with
  upstream `users-dawo` in Slice 3: adopt upstream's account, supply the hash.
- Mandatory hardening (PAM lockout, SSH policy, sysctl, time sync) applies to
  the appliance too; appliance services must work within it.
- GPL-3.0 modules are consumed as a flake input (aggregation) under the
  EUPL-1.2 compatibility already recorded (OQ-4).

## Alternatives considered

- **Desktop-only reuse** (`desktop-plasma` + `desktop-sddm-bzk`). Rejected:
  looks similar, is not the workplace (no hardening, apps, locale, printing,
  update status, user policy).
- **Fork the pilot host module.** Rejected (ADR 0001): parity would decay with
  every upstream change; importing the profile keeps parity by construction.
- **Keep auto-update on, pointed at our own overlay.** Rejected for v0.1:
  needs a hosted overlay repository (no remote yet, OQ-8) and contradicts the
  pinned-artifact model. Documented as a later option.
