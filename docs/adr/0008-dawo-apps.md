# ADR 0008: DAWO apps: a clean workplace, apps started on demand

- Status: **Accepted** (2026-10-11, maintainer: "Ja, ik ga akkoord"; with one
  configuration-only directory per app and a catalogue; names and the boot
  flow settled the same day). Open points: "Decisions still open".
- Date: 2026-10-11
- Deciders: maintainer (eywitteveen)
- Refs: #193 (design and two research rounds), #192 (data location), #151
  (Common Ground demo platform), #190 (Conduction apps), #195 (DAWO-Core
  v0.2.0); ADR 0001 (scope), ADR 0003 (workplace parity), ADR 0006 (live USB
  first), ADR 0007 (laptop profile)

## Context

Today the live USB boots the DAWO workplace and always starts one Ubuntu
24.04 guest with K3s that deploys Mijn Bureau (ADR 0006, 0007). The
maintainer wants more demo platforms (Valtimo/GZAC + Open Zaak with a front
end, La Suite numérique, Conduction apps) without a bigger, slower,
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

### What the user sees

1. **The platform is plain DAWO.** The USB SSD boots the DAWO workplace as
   DAWO-Core ships it; nothing is installed and no VM runs at boot.
2. **The app catalogue opens by itself** after login: one window with a card
   per app (logo, Dutch title, one or two sentences, a *Starten* button). It
   replaces today's status page, which already opens by itself.
3. **The user picks an app.** The catalogue checks memory, disk, KVM and
   internet first and says in plain Dutch what is missing, before anything
   changes (for example: "Mijn Bureau heeft ongeveer 25 GB ruimte nodig.
   Sluit een USB-schijf van 64 GB of groter aan."). Then it starts the guest
   (only now) and the app, shows the progress, and offers *Openen*.
4. **Next time it is quick:** the installed app stays on the data location,
   so a later start takes tens of seconds, not minutes.

### Names

One word everywhere, for the audience and in the repository:

| Thing | Name | Why |
|---|---|---|
| What you can start (Mijn Bureau, Valtimo, Open Zaak, Nextcloud, ...) | **app** | Everyone knows "app"; "component", "kit" or "package" are jargon. A suite like Mijn Bureau is one app to the user. |
| The list of apps | **catalogue**: `apps/catalog.toml`; in Dutch "app-catalogus" | Municipalities know the VNG *Softwarecatalogus*. |
| One app's directory | `apps/<id>/` | Next to the existing `apps/mijn-bureau/`. |
| One app's description | `apps/<id>/app.toml` | |
| The command | `dawo-app list`, `dawo-app start <id>`, `dawo-app stop <id>`, `dawo-app status`, `--json` | Like DAWO-Core's `dawo-verify` and `dawo-update-status`; reads as a sentence. The audience uses the buttons. |
| The NixOS module | `dawo.apps` (`flake.modules.nixos.services-apps`) | DAWO-Core layout, so it can be offered upstream. |

**App ids** are the product's own name as its maker writes it, lowercase,
words joined by hyphens: `mijn-bureau`, `valtimo`, `open-zaak`, `nextcloud`,
`openburo`. No supplier name, no version, no `-demo` (everything here is a
demo). An id never changes: it is in URLs
(`.../tree/main/apps/valtimo`) and documentation.

### One directory per app, configuration only

```
apps/
  catalog.toml          # schema = 1; one entry per app: id + path
  valtimo/
    app.toml            # schema = 1; the description (below)
    icon.svg            # the logo on the card
    values/*.yaml       # Helm values, as upstream's charts expect them
    manifests/*.yaml    # extra Kubernetes objects, incl. post-install Jobs
  open-zaak/
    ...
```

- `apps/catalog.toml` lists the apps and where they are. At first every
  entry points into this repository (`apps/<id>/`); later an entry may point
  to an app directory in another repository, pinned by revision and SHA-256,
  so a supplier can publish its own app without a change here.
- `app.toml` (TOML, read by Nix with `builtins.fromTOML`, no extra tooling)
  declares: the Dutch title and description; the product version; what to
  deploy, by reference to upstream's own artifacts (Helm chart or helmfile
  at a pinned revision, image digests; AGENTS rule 4); the requirements
  (memory, disk, CPU, KVM, network); the entry URL and a health check; the
  open standards it shows (for example OpenID.NLGov, ODF); a link to its
  `publiccode.yml`.
- **No shell scripts in an app directory.** Generic steps (Helm values,
  manifests, trusting the appliance CA, waiting for readiness, health
  checks) are done by `dawo-app`, driven by `app.toml`. A step only one app
  needs is a Kubernetes `Job` in `manifests/`, declared and reviewed like
  any other object.
- No new deployment format is invented: an app directory only points at and
  configures upstream's charts.

### Versions

- **One version per app at a time**, the product's own version (what the
  user sees, for example "Valtimo 12.4"), pinned in `app.toml` with the chart
  version and image digests below it.
- **Updating is a pull request** that changes the pins; git keeps the
  history. **An appliance release freezes the catalogue**: everyone with
  `v0.2.0` gets the same app versions.
- **Two major versions side by side only when really needed**, as two apps:
  `valtimo-11` next to `valtimo` (as nixpkgs does with `postgresql_15`).
- `catalog.toml` and `app.toml` carry `schema = 1`, so the format can change
  later without breaking old files.

### Underneath

- **One mechanism for Kubernetes stacks:** one shared guest VM with K3s,
  started when the first app starts; each app is a set of pinned Helm
  releases in it, with a combined resource check. A program that ships its
  own `nix run` demo may be listed as an external app, not hosted.
- **Data location, chosen once** (#193): an existing `DAWO_LOGS`, the free
  rest of the boot stick, or a folder on another USB drive, after a desktop
  consent dialog; **never the internal disk** (ADR 0006). Images are cached
  there as K3s airgap tarballs.
- Users in a dedicated group may start and stop apps (polkit), without sudo.

## Phases

- **A** (done, #192): disk image with a data partition grown on the first
  boot.
- **B1:** `dawo-app` (CLI), `apps/catalog.toml` and the first apps; the
  guest starts on demand instead of at boot. Mijn Bureau's driver
  (`apps/mijn-bureau/deploy.sh`, 14 phases of glue) is not
  configuration-only yet: it moves into `app.toml`, values and manifests
  step by step (post-install steps as Jobs) and shrinks as `dawo-app` takes
  over. An app whose charts are complete (Open Zaak, Valtimo) may be the
  first pure one.
- **B2:** the app catalogue window (cards) replacing the status page.
- **C:** Common Ground apps (Open Zaak / PodiumD, or Valtimo) and the
  Conduction apps as pinned Nextcloud apps (#151, #190).
- **D** (own decision, below): a NixOS microVM guest instead of the Ubuntu
  cloud image, a fallback without KVM, aarch64.

## Decisions still open

1. **Scope:** apps beyond Mijn Bureau go beyond ADR 0001's v0.1 scope
   ("one Ubuntu 24.04 VM, single-node K3s, Mijn Bureau"). Proposed: v0.2,
   after v0.1.0.
2. **Phase D:** replacing the Ubuntu 24.04 guest by a NixOS microVM
   (microvm.nix, `services.k3s`) changes ADR 0001; it would make the guest
   pure Nix and buildable for aarch64. Separate ADR when it is due.
3. **Where `dawo.apps` lives:** in this repository first; offered to
   DAWO-Core later, or kept as a separate add-on flake. To discuss in the
   DAWO Ontwikkeling chat with the other open questions in #193.
4. **Upstream contributions:** DAWO-Core requires AI use to be disclosed in
   contributions; this repository writes no AI attribution lines (AGENTS
   rule). Needed before anything is offered upstream.

## Consequences

- One kind of glue to maintain and test; a new app is mostly a directory
  plus a catalogue entry.
- The boot is faster and needs far less memory when only DAWO is shown; the
  first start of an app downloads and installs it (online install stays the
  assumption, ADR 0001).
- Apps whose images are amd64-only stay x86_64-only.
- An app that needs a profile like ADR 0007's is a deviation candidate
  (`docs/deviations.md`).

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
- **Other names:** "launch"/"launch kit" (an earlier draft of this ADR),
  "component" (Common Ground jargon), "package" (collides with Nix
  packages), "toepassing" (stiff): all less clear to the audience than
  "app".
