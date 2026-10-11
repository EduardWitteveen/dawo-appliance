# DAWO apps

> Experimental and unofficial. See `README.md`. Decision: ADR 0008
> (`docs/adr/0008-dawo-apps.md`).

An **app** is something a user can start on the DAWO workplace from the app
catalogue: Mijn Bureau today; later Valtimo, Open Zaak, Nextcloud and
others. Each app is one directory here, with configuration only.

```
apps/
  catalog.toml          # the catalogue: one [[app]] entry per app
  <id>/
    app.toml            # the app's description (below)
    icon.svg            # the logo on the card (optional for now)
    values/*.yaml       # Helm values, as upstream's charts expect them
    manifests/*.yaml    # extra Kubernetes objects, incl. post-install Jobs
```

No shell scripts in an app directory (ADR 0008). `apps/mijn-bureau/` is the
exception while its driver (`deploy.sh`) moves into configuration step by
step.

## `catalog.toml`

```toml
schema = 1

[[app]]
id = "mijn-bureau"   # lowercase words joined by hyphens; never renamed
path = "mijn-bureau" # directory under apps/
```

Later an entry may point to an app directory in another repository, pinned by
revision and SHA-256 (a supplier publishing its own app).

## `app.toml`

| Key | Type | Meaning |
|---|---|---|
| `schema` | `1` | Format version of this file |
| `id` | string | Same as the catalogue entry |
| `title`, `summary` | string | What the user sees on the card, in Dutch |
| `version` | string | The product's own version, as the user should see it |
| `url` | string | Where the app opens |
| `login` | string | Optional: the published demo account |
| `license` | string | SPDX identifier |
| `standards` | list | Open standards the app shows, as the audience knows them |
| `source.repo`, `source.rev` | string | Upstream repository and full 40-character commit (AGENTS rule 4) |
| `source.manifest` | string | Optional: key under `upstream` in `manifest/appliance-manifest.json` whose `rev` must be the same |
| `source.publiccode` | string | Path of `publiccode.yml` in that repository |
| `needs.memory_gib`, `needs.cpus`, `needs.disk_gib` | integer | What the app needs; checked before it starts |
| `needs.kvm`, `needs.internet` | bool | Hardware virtualisation; internet on the first start |
| `deploy.kind` | `helm`, `helmfile` or `driver` | How it is deployed (`driver`: transitional, Mijn Bureau only) |
| `deploy.profile` | string | Optional: the profile the driver uses |
| `health.url` | string | Answers when the app is ready |

**Versions:** one version per app at a time. Updating is a pull request that
changes the pins; an appliance release freezes the catalogue. Two major
versions side by side only as two apps (`valtimo-11` next to `valtimo`).

## Checks

`nix flake check` runs `apps-catalog` (offline): the catalogue and every
`app.toml` are read with `builtins.fromTOML`, the keys above are validated,
and pins named by `source.manifest` must equal the manifest. The catalogue is
also built as JSON for `dawo-app` and the app catalogue window:

```bash
nix build .#dawo-app && ./result/bin/dawo-app list
```

`dawo-app start`, `stop` and `status` follow in phase B1 (ADR 0008).
