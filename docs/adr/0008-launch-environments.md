# ADR 0008: Launch: environments started on demand from a clean workplace

- Status: **Accepted** (2026-10-11, maintainer: "Ja, ik ga akkoord"; one
  configuration-only directory per environment and a catalogue; the names
  Launch / Launcher / omgeving, the boot flow and data on the boot disk
  settled the same day). Open points: "Decisions still open".
- Date: 2026-10-11
- Deciders: maintainer (eywitteveen)
- Refs: #193 (design and two research rounds), #192 (disk image, DAWO_LOGS
  grown on first boot), #151 (Common Ground demo platform), #190 (Conduction
  apps), #195 (DAWO-Core v0.2.0), #203 (catalogue format); ADR 0001 (scope),
  ADR 0003 (workplace parity), ADR 0006 (live USB first), ADR 0007 (laptop
  profile)

## Context

Today the live USB boots the DAWO workplace and always starts one Ubuntu
24.04 guest with K3s that deploys Mijn Bureau (ADR 0006, 0007). The
maintainer wants more demo platforms (Valtimo/GZAC + Open Zaak with a front
end, PodiumD, La Suite numérique, Conduction apps) without a bigger, slower,
all-in-one image, and in a form the target audience (civil servants, policy
advisors, CISOs) understands at a glance.

Feedback from the DAWO community chat (2026-10-07) shaped the question:

- a DAWO-Core maintainer proposed an ISO per DAWO-Core release and demo
  platforms started on any DAWO workplace with one command (`launch
  mijnbureau-demo`, printing a `http://localhost:<port>` URL); as few kinds
  of "digital duct tape" as possible; devShell, NixOS container or microVM as
  the mechanism, and a concern about virtualisation on ARM;
- others asked for open standards and easy adoption by non-technical users,
  and for demos that feel fast.

Findings (sources in #193):

1. **No existing tool fits.** App stores (CasaOS, Runtipi, YunoHost, Umbrel,
   Cosmos) run Docker/compose only, several are not open source, none runs
   on NixOS. Kubernetes catalogues (Kubeapps, Glasskube) are archived.
   Selfhostix is a proof of concept. DAWO-Core has no such mechanism.
2. **Every wanted platform already ships as Helm charts + OCI images:** Mijn
   Bureau (helmfile), La Suite (charts in mijn-bureau-infra), Open Zaak and
   PodiumD (Maykin, Dimpact; PodiumD uses ZAC, not Valtimo), Valtimo
   (valtimo-platform charts). Conduction apps are Nextcloud apps.
3. **Re-implementing them as NixOS modules or in a devShell is a fork in all
   but name:** every version differs from upstream's pins, several parts
   exist only as OCI images, and the SSO, WOPI and Nextcloud post-install
   glue would be rewritten. A devShell fits a single program we build
   ourselves (like DAWO-Sextant's demo), not these suites.
4. **Mechanism choice is worth seconds, deployment minutes.** On the Dell the
   guest boots in ~30 s and K3s is Ready in ~50 s; Mijn Bureau's deployment
   takes 438-475 s even with cached images.
5. **ARM:** KVM is missing on Snapdragon X1 laptops under Linux; Open Zaak,
   Open Forms, Open Klant and Open Notificaties images are amd64-only.
   DAWO-Core is x86_64-only today.
6. Forum Standaardisatie's *Grip op digitale afhankelijkheid* names
   Kubernetes containers and Haven compliance as the portability route,
   which supports keeping upstream's charts.

## Decision

### Launch is its own thing

Launch is meant to become a project of its own, usable on other workplaces
(maintainer, 2026-10-11: "ik wil die launcher eigenlijk los van dawo maken
op termijn"). **Nothing in its names, code or user interface says "DAWO"**;
what is specific to this appliance (the domain `dawo.internal`, the
appliance CA, the `DAWO_LOGS` partition) is configuration passed to it.

### What the user sees

1. **The platform is plain DAWO.** The USB SSD boots the DAWO workplace as
   DAWO-Core ships it; nothing is installed and no VM runs at boot.
2. **The Launcher opens by itself** after login: one window with a card per
   environment (logo, Dutch title, one or two sentences, a *Starten*
   button). It replaces today's status page, which already opens by itself.
3. **The user picks an environment.** Launch checks memory, free space on
   `DAWO_LOGS`, KVM and internet first. When something falls short it
   **warns in plain Dutch before anything changes**, and the user may still
   go ahead (maintainer, 2026-10-11: "als mensen het toch willen proberen,
   dikke prima, maar dan weten ze het vooraf"). For example: "Er is nog 4 GB
   vrij op de USB-schijf; de Mijn Bureau-omgeving heeft ongeveer 25 GB nodig.
   Toch proberen?" (`launch` asks the same on the command line; `--yes`
   skips the question). Then it starts the guest (only now) and the
   environment, shows the progress, and offers *Openen*.
4. **One environment at a time.** Environments may share parts (Mijn Bureau
   contains Nextcloud, Valtimo uses Open Zaak); that does not matter, because
   to the user each is one whole that they start, look at and stop.
5. **Next time it is quick:** the installed environment stays on the USB
   disk, so a later start takes tens of seconds, not minutes.

### Names (maintainer, 2026-10-11)

| Thing | Name | Notes |
|---|---|---|
| The program and command | **Launch**: `launch` | `launch valtimo` starts the Valtimo environment; `launch --stop valtimo` stops it; `launch` (or `--list`) lists what there is; `--status`; `--json` for the Launcher. The verb is the command, so nothing is said twice. |
| The window where people choose | **Launcher** | "Open de Launcher en start de Valtimo-omgeving." |
| What you start (Mijn Bureau, Valtimo, Open Zaak, Nextcloud, PodiumD, ...) | **omgeving** (Dutch, for the audience); **environment** in the English repository and code | An environment may consist of many services; "app", "package" or "stack" fit less well. |
| The list | `environments/catalog.toml` | |
| One environment | `environments/<id>/environment.toml` | |
| The NixOS module | `services.launch` | Not tied to DAWO-Core's option namespace. |

**Environment ids** are the product's own name as its maker writes it,
lowercase, words joined by hyphens: `mijn-bureau`, `valtimo`, `open-zaak`,
`nextcloud`, `podiumd`. No supplier name, no version, no `-demo` (everything
here is a demo). An id never changes: it is in URLs
(`.../tree/main/environments/valtimo`) and documentation.

### One directory per environment, configuration only

```
environments/
  catalog.toml          # schema = 1; one [[environment]] entry: id + path
  valtimo/
    environment.toml    # schema = 1; the description (below)
    icon.svg            # the logo on the card
    values/*.yaml       # Helm values, as upstream's charts expect them
    manifests/*.yaml    # extra Kubernetes objects, incl. post-install Jobs
  open-zaak/
    ...
```

- `environments/catalog.toml` lists the environments and where they are. At
  first every entry points into this repository; later an entry may point to
  an environment directory in another repository, pinned by revision and
  SHA-256, so a supplier can publish its own environment without a change
  here.
- `environment.toml` (TOML, read by Nix with `builtins.fromTOML`, no extra
  tooling) declares: the Dutch title and description; the product version;
  what to deploy, by reference to upstream's own artifacts (Helm chart or
  helmfile at a pinned revision, image digests; AGENTS rule 4); the
  requirements (memory, disk, CPU, KVM, network); the entry URL and a health
  check; the open standards it shows (for example OpenID.NLGov, ODF); a link
  to its `publiccode.yml`. Format: `environments/README.md`.
- **No shell scripts in an environment directory.** Generic steps (Helm
  values, manifests, trusting the appliance CA, waiting for readiness, health
  checks) are done by Launch, driven by `environment.toml`. A step only one
  environment needs is a Kubernetes `Job` in `manifests/`, declared and
  reviewed like any other object.
- No new deployment format is invented: an environment directory only points
  at and configures upstream's charts.

### Versions

- **One version per environment at a time**, the product's own version (what
  the user sees, for example "Valtimo 12.4"), pinned in `environment.toml`
  with the chart version and image digests below it.
- **Updating is a pull request** that changes the pins; git keeps the
  history. **A release freezes the catalogue**: everyone with `v0.2.0` gets
  the same versions.
- **Two major versions side by side only when really needed**, as two
  environments: `valtimo-11` next to `valtimo` (as nixpkgs does with
  `postgresql_15`).
- `catalog.toml` and `environment.toml` carry `schema = 1`, so the format can
  change later without breaking old files.

### Underneath

- **One mechanism for Kubernetes stacks:** one shared guest VM with K3s,
  started when the first environment starts; each environment is a set of
  pinned Helm releases in it, with a resource check. A program that ships its
  own `nix run` demo may be listed as an external environment, not hosted.
- **Data lives on the boot disk only** (maintainer, 2026-10-11): the
  `DAWO_LOGS` partition of the USB disk the workplace boots from, as made by
  `dawo-stick.ps1` / `write-live-stick.sh` or grown on the first boot of the
  disk image (#192). No data-location chooser, no other USB drives, no
  consent dialogs, **never the internal disk** (ADR 0006): one layout to
  understand and to test. Without room there, the warning in point 3 says
  so; a user who goes ahead anyway may see the environment fail on a full
  disk. Images are cached there as K3s airgap tarballs.
- Users in a dedicated group may start and stop environments (polkit),
  without sudo.

## Phases

- **A** (done, #192): disk image with a data partition grown on the first
  boot.
- **B1:** Launch (CLI), the catalogue (done: format, check and listing,
  #203) and the first environments; the guest starts on demand instead of
  at boot. Mijn Bureau's driver (`apps/mijn-bureau/deploy.sh`, 14 phases of
  glue) is not configuration-only yet: it moves into `environment.toml`,
  values and manifests step by step (post-install steps as Jobs) and shrinks
  as Launch takes over. An environment whose charts are complete (Open Zaak,
  Valtimo) may be the first pure one.
- **B2:** the Launcher window (cards) replacing the status page.
- **C:** Common Ground environments (Open Zaak / PodiumD, or Valtimo) and the
  Conduction apps as pinned Nextcloud apps (#151, #190).
- **D** (own decision, below): a NixOS microVM guest instead of the Ubuntu
  cloud image, a fallback without KVM, aarch64.
- **Later:** Launch moves to a repository of its own; this appliance
  consumes it as a pinned flake input.

## Decisions still open

1. **Scope:** environments beyond Mijn Bureau go beyond ADR 0001's v0.1
   scope ("one Ubuntu 24.04 VM, single-node K3s, Mijn Bureau"). Proposed:
   v0.2, after v0.1.0.
2. **Phase D:** replacing the Ubuntu 24.04 guest by a NixOS microVM
   (microvm.nix, `services.k3s`) changes ADR 0001; it would make the guest
   pure Nix and buildable for aarch64. Separate ADR when it is due.
3. **When Launch moves out** to its own repository, and whether it is
   offered to the DAWO community; to discuss in the DAWO Ontwikkeling chat
   with the other open questions in #193.
4. **Upstream contributions:** DAWO-Core requires AI use to be disclosed in
   contributions; this repository writes no AI attribution lines (AGENTS
   rule). Needed before anything is offered upstream.

## Consequences

- One kind of glue to maintain and test; a new environment is mostly a
  directory plus a catalogue entry.
- The boot is faster and needs far less memory when only the workplace is
  shown; the first start of an environment downloads and installs it
  (online install stays the assumption, ADR 0001).
- Environments whose images are amd64-only stay x86_64-only.
- An environment that needs a profile like ADR 0007's is a deviation
  candidate (`docs/deviations.md`).

## Alternatives considered

- **devShell per platform** (services-flake, devenv, process-compose): no
  precedent for Nextcloud + Collabora + Keycloak SSO without root; state in
  the working directory; on a live stick it downloads into a RAM-backed Nix
  store. Kept for external single-program demos only.
- **NixOS modules from nixpkgs** for each service: a rewrite of upstream's
  deployment with different versions (Context 3).
- **An existing app store or PaaS** (CasaOS, Runtipi, Coolify, Portainer):
  Docker/compose only, floating tags, not on NixOS, some not open source.
- **A new descriptor standard** (Kubernetes Application CRD, CNAB, Score):
  inactive or unused by these upstreams.
- **Other names** (earlier drafts of this ADR, 2026-10-11): "launch kit",
  "app" with `dawo-app` / `dawo.apps` (tied to DAWO; "app" undersells a
  multi-service environment), `launch start <id>` (says "start" twice),
  "Proeftuin" (worn out in government, and was proposed as "DAWO
  Proeftuin"), "component" (Common Ground jargon), "package" (collides with
  Nix packages).
