# Releasing

> Experimental and unofficial. See `README.md`.

A release is a git tag `vX.Y.Z` plus a GitHub release with five assets: the
installer ISO, its SHA-256, the release manifest and its SHA-256, and the
SHA-256 of the live disk image. This follows the common GitHub practice (tag +
release assets); resolves OQ-8.

The live disk image itself, `dawo-appliance-live-vX.Y.Z.img` (~7 GB, written
with Rufus or Etcher, `docs/live-usb.md` 2a), is larger than GitHub's 2 GiB
per-asset limit. It is published on SourceForge, in
<https://sourceforge.net/projects/dawo-appliance/files/vX.Y.Z/> (maintainer
decision 2026-10-10, #192); the release notes link to it with its SHA-256. The
SourceForge project hosts only these files; code, issues and documentation
stay on GitHub.

## How the pieces fit

- The ISO carries the manifest and its checksum under `/etc/dawo-appliance/`.
  The checksum is the root of trust.
- `dawo-appliance-bootstrap` derives its default `--manifest-url` from the
  version of that shipped manifest:
  - release `X.Y.Z` → the asset of **exactly** tag `vX.Y.Z`
    (`https://github.com/EduardWitteveen/dawo-appliance/releases/download/vX.Y.Z/appliance-manifest.json`),
    never "latest";
  - development `X.Y.Z-dev` → the shipped copy (`file://`), as there is no
    release.
  Either way the download must match the baked-in SHA-256.
- The ISO is built from the tagged commit, so the manifest version inside the
  ISO equals the tag.

## Versions

SemVer (`X.Y.Z`); `appliance.version` in `manifest/appliance-manifest.json`
is the single source. Between releases it is the next version with `-dev`
(now `0.1.0-dev`). A release candidate `X.Y.Z-rc.N` goes through the same
procedure and becomes a GitHub **pre-release** (e.g. `v0.1.0-rc.1` for the
build that is tested on real hardware before `v0.1.0`). Every live image shows
its version and commit in the boot menu and in the status page footer
(`/etc/dawo-appliance/version`, #175).

## Procedure

Prerequisites: `verify.sh` green on `main` (`docs/verification-latest.md`),
ideally with `E2E=1`; `gh` logged in; Nix for the image builds; about 15 GB free for the live image.

1. `bash scripts/release.sh prepare X.Y.Z` — opens a PR that sets the manifest
   version. Merge it through the normal workflow.
2. `git switch main && git pull --ff-only`
3. `SF_USER=<sourceforge-user> bash scripts/release.sh publish X.Y.Z` — tags
   `vX.Y.Z`, builds the installer ISO and the live disk image from it,
   uploads the image and its `.sha256` to SourceForge with rsync (needs an
   SSH key on that SourceForge account), and creates a **draft** release with
   the five assets. Without `SF_USER` the image stays in `RELEASE_OUT`
   (default `~/dawo-release/vX.Y.Z/`) and the script prints the rsync
   command; uploading it in the SourceForge web UI (*Files*, *Add Folder*
   `vX.Y.Z`, *Add File*) works too. Re-entrant: a second run reuses the tag
   and re-uploads the assets.
4. The maintainer checks that the image is in the SourceForge folder, reviews
   the draft on GitHub and publishes it.
5. Open a PR that sets the manifest version to the next `-dev`
   (e.g. `0.2.0-dev`).

Both phases are idempotent where it matters and refuse on a dirty tree, a HEAD
that is not `origin/main`, or a version mismatch.
