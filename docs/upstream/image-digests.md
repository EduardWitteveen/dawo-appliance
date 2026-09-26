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

## Follow-up: make the Helmfile use these digests (Slice 6, issue #9)

**Implemented.** Recording digests protects nothing until the deployment
pulls by digest; `apps/mijn-bureau/deploy.sh`'s `phase_values` now writes a
`container:` overlay into the demo environment values
(`helmfile/environments/demo/mijnbureau.yaml.gotmpl`) with one entry per
`used_by` key path in this file, and `phase_wait_certs` ends with a
post-deploy check comparing every running pod's `imageID` against the pinned
digests.

The three-case split originally sketched here (bitnami `digest` field /
tag-only splice / hard-coded, needs a post-renderer) turned out, on reading
the pinned mijn-bureau-infra checkout's actual release-values templates
(`helmfile/apps/*/values*.yaml.gotmpl`), to collapse into **one** case for
every image this project resolves:

- Every one of those templates renders `tag: {{ .Values.container.<key>.tag }}`
  (or, for `cnpg_postgres`, splices it into an `imageName: repo:tag` string) —
  so `container.<key>.tag` is always a reachable override point via an
  environment values overlay.
- **None of them forward a `.digest` field from environment values.** Several
  of the vendored bitnami subcharts (postgresql, redis, minio, nginx) *do*
  support `image.digest` in the chart itself, but mijn-bureau-infra's own
  release-values template hardcodes `digest: ""` as a literal in the
  rendered YAML for those — not templated from `.Values` at all — so it
  can't be reached without patching upstream's own template (out of scope:
  we do not fork upstream, per the hard rules).
- So every image is pinned the same way: `tag: "<upstream tag>@sha256:<digest>"`.
  `repo:tag@sha256:digest` is a valid OCI/Docker reference (tag *and* digest;
  the digest wins), and containerd (K3s) accepts it. Verified by reading the
  pinned checkout; **never applied against a live cluster** (none available
  here), so a runtime surprise specific to one image/chart cannot be ruled
  out.
- No image among the 33 resolved here turned out to be hard-coded with no
  override point at all (the "needs a post-renderer" case). If a future
  mijn-bureau-infra revision adds one, that is a new deviation for
  `docs/deviations.md`, not something this mechanism can cover.

`openproject.hocuspocus` (the one unresolvable image) is skipped: no
`container.openproject.hocuspocus` override is emitted, and it is absent
from the post-deploy check's known-digest set, since there is no digest to
compare against and upstream disables it (`hocuspocus.enabled: false`)
regardless.

The post-deploy check (`verify_image_digests` in `deploy.sh`) is a
membership check, not a strict per-pod key mapping: it collects every
running container's `imageID` cluster-wide and reports which ones match none
of the pinned digests. That is expected noise for cluster-system pods this
project never pins (Traefik, CoreDNS, cert-manager, local-path-provisioner)
and only meaningful for `mb-*` application pods; it warns rather than fails
the deploy, since it has never been exercised against a real cluster.

`bash scripts/resolve-image-digests.sh --check` is now also part of
`scripts/verify.sh` (network + skopeo/nix required), so a re-pointed upstream
tag is caught in normal verification, not only on manual re-resolution.
