# Environments for Launch

> Experimental and unofficial. See `README.md`. Decision: ADR 0008
> (`docs/adr/0008-launch-environments.md`).

An **environment** (Dutch: *omgeving*) is something a user starts with
**Launch** to try it: Mijn Bureau, Valtimo and Nextcloud Common Ground today;
later Open Zaak, PodiumD and others. An environment may consist of many
services; to the user it is one whole that they start, look at and stop. One
runs at a time.

- `launch valtimo` starts the Valtimo environment; `launch --stop valtimo`
  stops it; `launch` lists what there is.
- Before starting, Launch checks memory, free space, hardware
  virtualisation and internet against the environment's `needs` and lists
  every shortfall in plain Dutch. The user may still go ahead: an
  interactive question, or `--yes`. `launch --check <id> [--json]` only
  checks (the Launcher uses the JSON for its cards; exit 3 = shortfalls).
- `launch --status [--json]` asks each environment's `health.url` and says
  whether it answers ("klaar op …") or not ("niet actief"). Read-only.
- The **Launcher** is the window where people choose: one card per
  environment.

Each environment is one directory here, with configuration only:

```
environments/
  catalog.toml          # the catalogue: one [[environment]] entry each
  <id>/
    environment.toml    # the description (below)
    icon.svg            # the logo on the card (optional for now)
    values/*.yaml       # Helm values, as upstream's charts expect them
    manifests/*.yaml    # extra Kubernetes objects, incl. post-install Jobs
```

No shell scripts in an environment directory (ADR 0008). Mijn Bureau is still
deployed by its driver, `apps/mijn-bureau/deploy.sh`, named in its
`environment.toml` (`deploy.kind = "driver"`), while its steps move into
configuration one at a time.

Launch is meant to become a project of its own: nothing in this format is
specific to one workplace.

## `catalog.toml`

```toml
schema = 1

[[environment]]
id = "mijn-bureau"   # lowercase words joined by hyphens; never renamed
path = "mijn-bureau" # directory under environments/
```

Later an entry may point to an environment directory in another repository,
pinned by revision and SHA-256 (a supplier publishing its own environment).

## `environment.toml`

| Key | Type | Meaning |
|---|---|---|
| `schema` | `1` | Format version of this file |
| `id` | string | Same as the catalogue entry |
| `title`, `summary` | string | What the user sees on the card, in Dutch |
| `version` | string | The product's own version, as the user should see it |
| `url` | string | Where the environment opens |
| `login` | string | Optional: the published demo account |
| `license` | string | SPDX identifier |
| `standards` | list | Open standards it shows, as the audience knows them |
| `source.repo`, `source.rev` | string | Upstream repository and full 40-character commit (AGENTS rule 4) |
| `source.manifest` | string | Optional: key under `upstream` in `manifest/appliance-manifest.json` whose `rev` must be the same |
| `source.publiccode` | string | Path of `publiccode.yml` in that repository |
| `needs.memory_gib`, `needs.cpus`, `needs.disk_gib` | integer | What it needs; Launch warns beforehand when the laptop falls short (the user may go ahead) |
| `needs.kvm`, `needs.internet` | bool | Hardware virtualisation; internet on the first start |
| `deploy.kind` | `helm`, `helmfile` or `driver` | How it is deployed (`driver`: a script of ours; Mijn Bureau, and the compose environments below) |
| `deploy.driver` | string | With `driver`: the script in this repository |
| `deploy.profile` | string | Optional: the profile the driver uses |
| `deploy.compose_file`, `deploy.compose_profile`, `deploy.compose_override` | string | Optional, compose environments: upstream's compose file, the profile it is started with, and our override file (path in this directory) |
| `health.url` | string | Answers when the environment is ready |
| `notice.title`, `notice.text` | string | Optional: shown before the environment starts (Launcher card and `launch`), for example its terms when its license is not known (#261) |
| `notice.seconds` | integer | Optional: how long the Launcher shows it before starting (default 60); "Nu starten" and "Niet starten" end it |
| `notice.level` | `info` or `danger` | Optional: `danger` shows it in red |
| `components` | list of tables | Optional (#273): what runs, one entry per source repository, each `name`, `repo`, `license` (SPDX identifier; `NOASSERTION` when the repository has no licence file; `LicenseRef-proprietary` when it is explicitly not open source) and `evidence` (where that was found). Each part gets a class (nix/launch.nix): *open* (an open-source licence, or a choice that includes one; `LicenseRef-Ubuntu-main` and `LicenseRef-Alpine-main` for distributions whose packages are open source by their own policy), *restricted* (source available only: SSPL, RSAL, BUSL), *unknown* (`NOASSERTION`) or *closed* (`LicenseRef-proprietary...`). The test behind it: can we keep running and developing it when the supplier stops? The card is green when all parts are open, yellow when some are restricted or unknown, red when one is closed, and says why; red also shows a notice before the start, unless the environment has its own. An unclassified licence id fails the check |
| `links` | list of tables | Optional: what runs next to it, each `title`, `url` and an optional `login`; the Launcher lists them on the card once the environment is ready |

**Versions:** one version per environment at a time. Updating is a pull
request that changes the pins; a release freezes the catalogue. Two major
versions side by side only as two environments (`valtimo-11` next to
`valtimo`).

## The `launch` command

The command is `launch/launch.sh`, packaged by `nix/launch.nix`. Nothing in
it is specific to one workplace; the appliance sets:

| Variable | Default | Meaning |
|---|---|---|
| `LAUNCH_DATA_PATH` | `/var/lib/launch` | Where environments keep their data (free space is checked here) |
| `LAUNCH_RESERVE_GIB` | `6` | Memory kept for the workplace itself |
| `LAUNCH_INTERNET_URL` | `https://github.com/` | Reachable when there is internet |

Exit codes: 0 ok, 1 usage or unknown environment, 2 not set up on this
machine, 3 shortfalls and not started.

## Starting and stopping (`services.launch`)

The NixOS module `nix/launch-module.nix` binds each environment to the systemd
units that start it (`services.launch.environments.<id>.units`), writes
`/etc/launch/config.json`, and lets members of the `launch` group start and
stop exactly those units without sudo (polkit). `launch <id>` starts them in
order (after the preflight); `launch --stop <id>` stops them in reverse;
`launch --status` says "wordt gestart" while they run but the environment does
not answer yet. `services.launch.autostart` starts environments at boot. On
the live USB (`hosts/appliance/live-launch.nix`) Mijn Bureau is bound to the
guest and its deployment; nothing starts at boot, the Launcher window opens
at login (ADR 0008, B2).

While an environment starts it may report its progress
(`services.launch.environments.<id>.progressFile`, #232): a JSON object
`{step, steps, label, started, since, expected, error}` (times in seconds
since the epoch; `expected` is how long this step should take, `error` a
message when it failed). `launch --status` passes it on, and the Launcher
shows a bar for the whole start and one for the current step. The Mijn Bureau
runner writes it, with the step durations of the last run on this machine.

## Compose environments (Valtimo, Nextcloud Common Ground)

Some products ship their demo as a Docker Compose file. Those environments
run that file as upstream ships it, at a pinned commit, plus one override
file of ours (`<id>/compose/override.yaml`: images by digest, versions,
memory limits), on a Docker Engine in the same guest as Mijn Bureau
(`dawo-docker`, D43). Their driver (`apps/<id>/deploy.sh`) runs in phases
from a host runner (`hosts/appliance/live-<id>.nix`) that reports progress to
the Launcher and forwards upstream's `localhost` ports to the guest while the
environment runs.

One at a time: Launch stops the other environment's units first, and each
driver stops K3s and the running containers of every other compose project
(also after the engine starts, since upstream's restart policies bring them
back). Data stays in their volumes.

| Environment | Upstream | Opens at | Login |
|---|---|---|---|
| `valtimo` | gzac-docker-compose `v/13`, `--profile demo` | `http://localhost/` | `admin` / `admin` |
| `nextcloud-commonground` | ConductionNL/dossiq `dossiq-compose.yaml` | `http://localhost:8609/apps/dossiq/` | `admin` / `admin` |

Nextcloud Common Ground adds to upstream's four apps (OpenRegister, Thematiq,
Integriq, Dossiq) three more of Conduction's (OpenCatalogi, Pipelinq,
Portaliq), all stable GitHub releases checked by SHA-256 before they are
unpacked, and runs the apps' own demo data (`dossiq:demo:seed`,
`pipelinq:demo:seed`). Pins: `manifest/appliance-manifest.json`
`nextcloud_commonground`; deviations D44-D46.

## Checks

`nix flake check` runs `environments-catalog` (offline): the catalogue and
every `environment.toml` are read with `builtins.fromTOML`, the keys above are
validated, and pins named by `source.manifest` must equal the manifest.

```bash
nix build .#launch && ./result/bin/launch
```

The check also runs the preflight against a fake small and a fake large
laptop (memory, free space, KVM and internet overrides), and starting,
stopping and status against a fake systemctl.
