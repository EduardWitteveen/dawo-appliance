# ADR 0008: `launch`: demo platforms as components started on demand

- Status: **Accepted** (2026-10-11, maintainer: "Ja, ik ga akkoord", with
  one directory per component, configuration only, and an index; decision
  2). Open points in "Decisions the maintainer still has to take".
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
all-in-one image.

Feedback from the DAWO community chat (2026-10-07) shaped the question:

- a DAWO-Core maintainer proposed an ISO per DAWO-Core release and demo
  platforms started on any DAWO workplace with one command, such as
  `launch mijnbureau-demo`, which prints a `http://localhost:<port>` URL; as
  few kinds of "digital duct tape" as possible; devShell, NixOS container or
  microVM as the mechanism, and a concern about virtualisation on ARM;
- others asked for open standards and easy adoption by non-technical users,
  and for demos that feel fast.

Findings (sources in #193):

1. **No existing tool fits.** App stores (CasaOS, Runtipi, YunoHost, Umbrel,
   Cosmos) run Docker/compose only, several are not open source, none runs
   on NixOS. Kubernetes catalogues (Kubeapps, Glasskube) are archived.
   Selfhostix is a proof of concept. DAWO-Core has no component mechanism.
2. **Every wanted platform already ships as Helm charts + OCI images:** Mijn
   Bureau (helmfile), La Suite (charts in mijn-bureau-infra), Open Zaak and
   PodiumD (Maykin, Dimpact; PodiumD uses ZAC, not Valtimo), Valtimo
   (valtimo-platform charts). Conduction apps are Nextcloud apps.
3. **Re-implementing them as NixOS modules or in a devShell is a fork in all
   but name:** every version differs from upstream's pins, several
   components exist only as OCI images, and the SSO, WOPI and Nextcloud
   post-install glue would be rewritten. A devShell fits a single program we
   build ourselves (like DAWO-Sextant's demo), not these suites.
4. **Mechanism choice is worth seconds, deployment minutes.** On the Dell the
   guest boots in ~30 s and K3s is Ready in ~50 s; Mijn Bureau's deployment
   takes 438-475 s even with cached images.
5. **ARM:** KVM is missing on Snapdragon X1 laptops under Linux; Open Zaak,
   Open Forms, Open Klant and Open Notificaties images are amd64-only.
   DAWO-Core is x86_64-only today.
6. Forum Standaardisatie's *Grip op digitale afhankelijkheid* names
   Kubernetes containers and Haven compliance as the portability route,
   which supports keeping upstream's charts.

## Decision (proposed)

1. **A NixOS module `dawo.launch`**, laid out like a DAWO-Core block
   (`flake.modules.nixos.services-launch`, options under `dawo.launch.*`)
   so it can be offered upstream later. It works the same on the live USB
   and on an installed workplace.
2. **Launch kits: one directory per component, configuration only**
   (maintainer, 2026-10-11). A kit holds everything needed to install that
   component, and no scripts:

   ```
   launch/
     index.toml            # the kits: name + path; later also url + rev + sha256
     mijnbureau/
       kit.toml            # the kit description (below)
       values/*.yaml       # Helm values, as upstream's charts expect them
       manifests/*.yaml    # extra Kubernetes objects, incl. post-install Jobs
     valtimo/
       kit.toml
       ...
   ```

   - `launch/index.toml` lists the kits and where they are. At first every
     entry points into this repository (`launch/<name>/`); later an entry may
     point to a kit in another repository, pinned by revision and SHA-256,
     so a supplier can publish its own kit without a change here.
   - `kit.toml` (TOML, read by Nix with `builtins.fromTOML`, no extra
     tooling) declares: what to deploy, by reference to upstream's own
     artifacts (Helm chart or helmfile at a pinned revision, image digests;
     AGENTS rule 4); the requirements (memory, disk, CPU, KVM, network); the
     entry URL, a Dutch name and help text, a health check; the open
     standards it shows (for example OpenID.NLGov, ODF) and a link to its
     `publiccode.yml`.
   - **No shell scripts in a kit.** Generic steps (Helm values, manifests,
     trusting the appliance CA, waiting for readiness, health checks) are
     done by `launch` itself, driven by the kit. A step that only one
     platform needs is a Kubernetes `Job` in `manifests/`, so it is still
     declared, reviewed and run like any other object.
   - No new deployment format is invented: the kit only points at and
     configures upstream's charts.
3. **One mechanism for Kubernetes stacks:** one shared guest VM with K3s;
   each component is a set of pinned Helm releases in it, with a combined
   resource check. Mijn Bureau's deployment driver (`apps/mijn-bureau/`)
   becomes the first component's backend. A program that ships its own
   `nix run` demo may be listed as an external component, not hosted.
4. **A CLI, `launch`:** `launch` lists components; `launch <name>` checks the
   requirements, installs or starts the component and prints its URL;
   `launch stop <name>`; `launch status`; `--json` for the GUI. Users in a
   dedicated group may start and stop components (polkit), without sudo.
5. **Preflight with Dutch messages.** If memory, disk, KVM or network is
   missing, `launch` stops before changing anything and says what to do (for
   example: "Mijn Bureau heeft ongeveer 25 GB ruimte nodig. Sluit een
   USB-schijf van 64 GB of groter aan.").
6. **A data location, chosen once**, as in #193: an existing `DAWO_LOGS`, the
   free rest of the boot stick, or a folder on another USB drive, after a
   desktop consent dialog; **never the internal disk** (ADR 0006).
7. **Speed:** the deployed state stays on the data location, so a later
   start reuses it (tens of seconds, not minutes); images are cached there
   as K3s airgap tarballs; only the chosen component starts.
8. **GUI:** one card per component on the existing status page (Starten /
   Stoppen / Openen, the preflight message, progress), backed by
   `launch --json`.

## Phases

- **A** (done in #192): disk image with a data partition grown on the first
  boot.
- **B1:** the `launch` CLI, `launch/index.toml` and the first kit. Mijn
  Bureau's current driver (`apps/mijn-bureau/deploy.sh`, 14 phases of glue)
  is not configuration-only yet: it moves into `launch/mijnbureau/` step by
  step (values and manifests first, post-install steps as Jobs), and the
  driver shrinks as the engine takes over. A platform whose charts are
  complete (Open Zaak, Valtimo) may become the first pure kit. Deployed
  state kept on the data location.
- **B2:** the GUI cards.
- **C:** a Common Ground component (Open Zaak / PodiumD charts, or Valtimo
  charts) and the Conduction apps as pinned Nextcloud apps (#151, #190).
- **D** (needs its own decision, see below): a NixOS microVM guest instead
  of the Ubuntu cloud image, a fallback without KVM, aarch64.

## Decisions the maintainer still has to take

1. ~~Accept this direction~~ — accepted 2026-10-11, with launch kits
   (decision 2).
2. **Scope:** `launch` and more platforms go beyond ADR 0001's v0.1 scope
   ("one Ubuntu 24.04 VM, single-node K3s, Mijn Bureau"). Proposed: v0.2.
3. **Phase D:** replacing the Ubuntu 24.04 guest by a NixOS microVM
   (microvm.nix, `services.k3s`) changes ADR 0001; it would make the guest
   pure Nix and buildable for aarch64. Separate ADR when it is due.
4. **Where `dawo.launch` lives:** in this repository first; offered to
   DAWO-Core later, or kept as a separate add-on flake. To discuss in the
   DAWO Ontwikkeling chat together with the other open questions in #193.
5. **Upstream contributions:** DAWO-Core requires AI use to be disclosed in
   contributions; this repository writes no AI attribution lines (AGENTS
   rule). Needed before anything is offered upstream.

## Consequences

- One kind of glue to maintain and test; each new platform is mostly a
  registry entry plus pinned charts.
- The live image stays the DAWO workplace plus the guest; platforms are
  downloaded on first use and cached on the data location (online install
  stays the assumption, ADR 0001).
- Components whose images are amd64-only stay x86_64-only.
- Every component is a deviation candidate (`docs/deviations.md`) where it
  needs a profile like ADR 0007's.

## Alternatives considered

- **devShell per platform** (services-flake, devenv, process-compose): no
  precedent for Nextcloud + Collabora + Keycloak SSO without root; state in
  the working directory; on a live stick it downloads into a RAM-backed Nix
  store. Kept for external single-program demos only.
- **NixOS modules from nixpkgs** for each service: a rewrite of upstream's
  deployment with different versions (see Context 3).
- **An existing app store or PaaS** (CasaOS, Runtipi, Coolify, Portainer):
  Docker/compose only, floating tags, not on NixOS, some not open source.
- **A new descriptor standard** (Kubernetes Application CRD, CNAB, Score):
  inactive or unused by these upstreams.
