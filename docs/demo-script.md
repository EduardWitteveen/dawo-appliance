# Municipal 5-Minute Demonstration Script

This script is designed for Policy Advisors or Innovation Officers presenting the `dawo-appliance` to municipal decision-makers (Aldermen, CISOs, or Department Heads). It highlights digital sovereignty, non-destructive evaluation, and the exact open-source workplace experience.

**Prerequisites:** A test laptop prepared according to [`demo-hardware.md`](demo-hardware.md) and a bootable USB drive containing the appliance ISO.

---

## 0:00 – 1:00 | The Introduction & Safe Boot
*Action: Insert the USB drive and boot the laptop into the live environment.*

**Talking Points:**
- "We are exploring digital sovereignty and reducing our dependence on single-vendor cloud platforms like Microsoft 365, in line with national guidelines."
- "What I am showing you is the DAWO (Digitale Autonome Werkplek Overheid) appliance. It runs entirely on this local machine."
- "Right now, we are booting a 'live' environment. This is completely non-destructive—it has not touched the laptop's hard drive yet. We can evaluate it safely on any decommissioned municipal hardware."

## 1:00 – 2:00 | Transparency & The Install Plan
*Action: Open the terminal and run `dawo-appliance-bootstrap plan`.*

**Talking Points:**
- "Trust and transparency are core to open source. Before we install anything, the appliance can generate a 'plan'."
- *Point to the screen output:* "It shows exactly what it will do: which disk it will format and what cryptographic signatures it verified. There are no hidden background telemetry or undocumented cloud connections."
- "Because this is defined in code (NixOS), this exact setup is reproducible across all our municipalities. No more manual configuration drift."

## 2:00 – 3:30 | The Workplace Experience
*Action: Assume the laptop is now installed and boot into the DAWO desktop.*

**Talking Points:**
- "This is the exact KDE Plasma desktop environment our civil servants would see. It is clean, accessible, and familiar."
- *Acknowledge the welcome screen:* "You'll notice the 'experimental/unofficial' banner. This is a prototype meant to demonstrate the technology stack, not the final production branding."
- "Everything you see here is governed by open standards. We control the update cycle, the data storage, and the cryptography."

## 3:30 – 5:00 | Mijn Bureau & Data Sovereignty
*Action: Open the browser to the local Mijn Bureau dashboard.*

**Talking Points:**
- "Behind the scenes, this laptop is running its own local cloud (a K3s cluster). What you see here is the 'Mijn Bureau' suite."
- *Click through Nextcloud, Collabora (office suite), or Grist (spreadsheets):* "These are full-featured, open-source alternatives to OneDrive, Word, and Excel."
- "The key differentiator: **All of this data stays here.** When we type a document or build a spreadsheet in this environment, it never leaves our municipal network unless we explicitly allow it. This solves our data classification and BIO compliance challenges."

---

## FAQ Handling for Presenters

- **"Can we connect this to Active Directory/Entra ID?"**
  *Answer:* This v0.1 appliance focuses on a standalone demonstration of the core components. Production deployments of DAWO support standard identity federation (OIDC/SAML).
- **"Is it secure?"**
  *Answer:* It uses reproducible builds, explicit cryptographic pinning, and local orchestration. Hardening steps (like full disk encryption) are documented as post-MVP items.
- **"Do we need specialized Linux administrators?"**
  *Answer:* The underlying NixOS configuration is declarative. Once set up by the central engineering team, deploying or updating it is a standardized, automated process.
