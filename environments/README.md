# Environments for Launch

> Experimental and unofficial. See `README.md`. Decision: ADR 0008
> (`docs/adr/0008-launch-environments.md`).

An **environment** (Dutch: *omgeving*) is something a user starts with
**Launch** to try it: the Mijn Bureau environment today; later Valtimo, Open
Zaak, Nextcloud, PodiumD and others. An environment may consist of many
services; to the user it is one whole that they start, look at and stop. One
runs at a time.

- `launch valtimo` starts the Valtimo environment; `launch --stop valtimo`
  stops it; `launch` lists what there is.
- Before starting, Launch checks memory, free space, hardware
  virtualisation and internet against the environment's `needs` and lists
  every shortfall in plain Dutch. The user may still go ahead: an
  interactive question, or `--yes`. `launch --check <id> [--json]` only
  checks (the Launcher uses the JSON for its cards; exit 3 = shortfalls).
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
| `deploy.kind` | `helm`, `helmfile` or `driver` | How it is deployed (`driver`: transitional, Mijn Bureau only) |
| `deploy.driver` | string | With `driver`: the script in this repository |
| `deploy.profile` | string | Optional: the profile the driver uses |
| `health.url` | string | Answers when the environment is ready |

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

Exit codes: 0 ok, 1 usage or unknown environment, 2 not available yet,
3 shortfalls and not started.

## Checks

`nix flake check` runs `environments-catalog` (offline): the catalogue and
every `environment.toml` are read with `builtins.fromTOML`, the keys above are
validated, and pins named by `source.manifest` must equal the manifest.

```bash
nix build .#launch && ./result/bin/launch
```

The check also runs the preflight against a fake small and a fake large
laptop (memory, free space, KVM and internet overrides). Starting and stopping
themselves follow in phase B1 (ADR 0008).
