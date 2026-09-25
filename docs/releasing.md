# Releasing

> Experimental and unofficial. See `README.md`.

A release is a git tag `vX.Y.Z` plus a GitHub release with four assets: the
installer ISO, its SHA-256, the release manifest and its SHA-256. This follows
the common GitHub practice (tag + release assets); resolves OQ-8.

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

## Procedure

Prerequisites: `verify.sh` green on `main` (`docs/verification-latest.md`),
ideally with `E2E=1`; `gh` logged in; Nix for the ISO build.

1. `bash scripts/release.sh prepare X.Y.Z` — opens a PR that sets the manifest
   version. Merge it through the normal workflow.
2. `git switch main && git pull --ff-only`
3. `bash scripts/release.sh publish X.Y.Z` — tags `vX.Y.Z`, builds the ISO from
   it and creates a **draft** release with the four assets. Re-entrant: a
   second run reuses the tag and re-uploads the assets.
4. The maintainer reviews the draft on GitHub and publishes it.
5. Open a PR that sets the manifest version to the next `-dev`
   (e.g. `0.2.0-dev`).

Both phases are idempotent where it matters and refuse on a dirty tree, a HEAD
that is not `origin/main`, or a version mismatch.
