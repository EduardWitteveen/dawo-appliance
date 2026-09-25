# Container image digests (OQ-5)

`manifest/image-digests.json` maps every container image that Mijn Bureau
references at the pinned mijn-bureau-infra revision to its immutable
`sha256:` manifest digest. Produced and refreshed by
`scripts/resolve-image-digests.sh`; checked offline by
`tests/test-image-digests.sh`. Never edit the JSON by hand.

## Why digests

Upstream pins images by **tag** in
`helmfile/environments/default/container.yaml.gotmpl`. A tag is a mutable
pointer: a registry (or anyone with push rights) can re-point
`nextcloud:34.0.1-apache` to different bytes tomorrow without any change in
upstream Git. Our rule is "pin everything" (ADR 0001), so we record the digest
each tag pointed at on the day we inspected it. A digest is content-addressed:
`repository@sha256:...` can only ever yield the same image.

Per image the file records two digests, because most images are multi-arch:

| Field | Meaning |
|-------|---------|
| `digest` | SHA-256 of the top-level manifest the tag points at (the manifest list / OCI index for a multi-arch image). This is what `skopeo inspect --format '{{.Digest}}'` prints and what `repository@sha256:...` pulls with. |
| `amd64_digest` | SHA-256 of the `linux/amd64` platform manifest inside that index; equal to `digest` for a single-platform amd64 image. Useful for comparing what actually runs in the VM (x86-64 only in v0.1). |
| `used_by` | The key path(s) in `container.yaml.gotmpl` that reference the image (e.g. `docs.backend`, `minio_shell, osShell`). |
| `error` | Only present when the registry refused anonymous inspection; then both digests are `null`. |

`source` names the upstream repo, revision and file the list was read from;
`resolved` is the UTC date of the run. Output is sorted, so a re-run without
upstream or registry changes produces an identical file except for the date.

## How to refresh

Needs network access and `skopeo` (falls back to `nix shell` from the nixpkgs
revision pinned in the manifest when skopeo is not on `PATH`). In WSL:

```sh
bash scripts/resolve-image-digests.sh          # rewrites manifest/image-digests.json
bash tests/test-image-digests.sh               # offline sanity check (also runs on Git Bash)
```

The resolver reads `mijn_bureau.rev` from `manifest/appliance-manifest.json`,
so bumping the upstream revision there and re-running is the whole workflow.
The resolver exits 1 when any image stays unresolved (see below) even though
it has written the file; that is a warning, not a failure of the run.

## How `--check` detects a re-pointed tag

```sh
bash scripts/resolve-image-digests.sh --check
```

resolves everything again **without writing** and compares against the
committed file. It exits non-zero when:

- an upstream image has no entry in the committed file (`MISSING`), or the
  file lists an image upstream no longer has (`STALE`);
- a digest differs from what the registry serves now (`CHANGED`): the tag was
  re-pointed upstream. That is exactly the event digest pinning exists to
  catch; inspect the new image before refreshing the file;
- an image that was pinned can no longer be resolved (`UNRESOLVED now`), or
  one recorded as unresolvable has become pullable (`NOW RESOLVABLE`).

An image that was and still is unresolvable is only a `WARN`.

## State on 2026-09-25 (rev `b2ae545`)

34 unique images (35 references), **33 resolved**, 1 unresolvable:
`ghcr.io/openproject/hocuspocus:main-defdb238` returns `403 Forbidden` on the
anonymous bearer-token request (the package is not public on ghcr.io).
Upstream's `helmfile/apps/openproject/values.yaml.gotmpl` sets
`hocuspocus.enabled: false`, so the single-VPS deployment never pulls it; it
is not in the manifest's `images_by_tag` and the test only warns about it.
Everything the manifest's `images_by_tag` lists (17 images) is pinned.
Notable: Docker Hub images are keyed as `docker.io/...` even where upstream
writes `registry-1.docker.io`; both hostnames serve the same content.

## Follow-up: make the Helmfile use these digests (Slice 6)

Recording digests protects nothing until the deployment pulls by digest.
Upstream's values take `registry` / `repository` / `tag` per image, and most
charts render `{{ registry }}/{{ repository }}:{{ tag }}`. The approach for
Slice 6, per chart, without forking upstream:

- **Charts that support a `digest` field** (bitnami-style `image.digest`, the
  `bitnamilegacy/*` images, Keycloak, MinIO, PostgreSQL, Redis, nginx): pass
  `digest: sha256:...` from `image-digests.json`; bitnami's `common.images.image`
  helper then renders `repository@sha256:...` and ignores the tag.
- **Charts that only take `tag`**: set `tag: "<tag>@sha256:<digest>"`. OCI
  references of the form `repo:tag@sha256:digest` are valid and the digest
  wins; container runtimes (containerd in K3s) accept this. Verify per chart
  that the tag is not otherwise parsed (e.g. for version comparisons).
- **Charts that hard-code `image: repo:tag`** (no repository/tag split): need
  an upstream change or a Kustomize/`strategic-merge` post-render; list them
  as deviations in ADR 0003's table.

The mechanism: generate an environment values overlay
(`container.yaml` with `digest` / `tag@sha256` per key path from `used_by`)
from `image-digests.json` at deploy time in `apps/`, and add a post-deploy
check that every running pod's `imageID` ends in a digest from the file.
Not implemented in this slice.
