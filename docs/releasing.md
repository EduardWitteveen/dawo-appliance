# Releasing

> Experimental and unofficial. See `README.md`.

A release is a git tag `vX.Y.Z` plus two places to download from:

- **SourceForge**, folder
  <https://sourceforge.net/projects/dawo-appliance/files/vX.Y.Z/>: the live
  disk image `dawo-appliance-live.img` (~7 GB, written with Rufus or
  balenaEtcher, `docs/live-usb.md` 2a), its `.sha256` and `SHA256SUMS`. The
  image is larger than GitHub's 2 GiB per-asset limit (maintainer decision
  2026-10-10, #192). The SourceForge project hosts only these files; code,
  issues and documentation stay on GitHub.
- **GitHub release** `vX.Y.Z`: the release notes (generated from
  `CHANGELOG.md`, with the SourceForge link and the image's SHA-256) and four
  small assets: `SHA256SUMS`, `dawo-appliance-live.img.sha256`, the release
  manifest `appliance-manifest.json` and its `.sha256`. This follows the
  common GitHub practice (tag + release assets); resolves OQ-8.

The installer ISO is no longer part of a release (since v0.1.0-rc.1, #175):
ADR 0006 made the live USB the default, and building and hosting a second
large image per release costs time without a user for it. It can still be
built from the tag with `nix build .#installer-iso`; whether v0.1 ships the
installed-to-disk path at all is open (#16, #17). The manifest stays a release
asset, so the installer's bootstrap keeps finding the manifest of its own
version (below).

## How the pieces fit

- Every image carries the manifest and its checksum under
  `/etc/dawo-appliance/`. The checksum is the root of trust.
- `dawo-appliance-bootstrap` (installer path) derives its default
  `--manifest-url` from the version of that shipped manifest:
  - release `X.Y.Z` → the asset of **exactly** tag `vX.Y.Z`
    (`https://github.com/EduardWitteveen/dawo-appliance/releases/download/vX.Y.Z/appliance-manifest.json`),
    never "latest";
  - development `X.Y.Z-dev` → the shipped copy (`file://`), as there is no
    release.
  Either way the download must match the baked-in SHA-256.
- The image is built from the tagged commit, so the manifest version inside
  it equals the tag, and the boot menu and status page show that commit.

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
ideally with `E2E=1`; `gh` logged in; Nix (WSL or Linux) for the image build;
about 15 GB free. Build from the normal git checkout (`.`), not a worktree
with a `path:` flake: the image would lose its commit and carry `.git` (#248).

`scripts/release.sh` does nothing destructive by default: without arguments it
is `plan`, which shows the version, the checks and what every step would do,
and builds, writes, uploads or pushes nothing. The steps are options and can
be combined; they run in the order below.

1. `bash scripts/release.sh prepare 0.1.0-rc.1` — opens a PR that sets the
   manifest version (and its checksum) and turns `## [Unreleased]` in
   `CHANGELOG.md` into `## [0.1.0-rc.1] - <today>` with a fresh, empty
   `[Unreleased]` above it. Review the section text in the PR: it becomes the
   release notes. Merge it through the normal workflow.
2. `git switch main && git pull --ff-only`, then `bash scripts/release.sh plan`
   until it says **READY**. `bash scripts/release.sh notes` previews the notes.
3. In WSL/Linux: `bash scripts/release.sh --build --stage ~/dawo-release/v0.1.0-rc.1/stage --sourceforge-command`
   - `--build`: `nix build .#appliance-live-img`, out-link and commit under
     `RELEASE_OUT/vX.Y.Z/` (default `~/dawo-release/vX.Y.Z/`);
   - `--stage DIR`: copies the image, its `.sha256`, the manifest and its
     `.sha256` to `DIR`, checks both checksums, writes `SHA256SUMS` and
     `RELEASE-NOTES.md`;
   - `--sourceforge-command`: prints the `rsync` command for
     `frs.sourceforge.net`.
4. **The maintainer uploads** the three files (image, `.sha256`,
   `SHA256SUMS`) with their own SSH key on the SourceForge account: run the
   printed `rsync` command with `<sourceforge-user>` filled in, or
   `SF_USER=<user> bash scripts/release.sh --stage DIR --sourceforge-upload`
   with the key in an ssh-agent, or the web UI (*Files*, *Add Folder*
   `vX.Y.Z`, *Add File*). The script never stores or asks for credentials.
5. `bash scripts/release.sh --stage DIR --github` — tags `vX.Y.Z` on the built
   commit, pushes the tag and creates a **draft** GitHub release (a
   pre-release for `-rc.N`) with the notes and the four small assets. A second
   run updates the notes and assets of the draft; a published release is
   never touched.
6. The maintainer checks that the SourceForge link downloads and the SHA-256
   matches, reviews the draft on GitHub and publishes it. The script never
   publishes.
7. Set `softwareVersion` and `releaseDate` in `publiccode.yml` for a final
   (non-rc) release, and open a PR that sets the manifest version to the next
   `-dev` (e.g. `0.2.0-dev`).

Every step refuses a `-dev` version, a dirty tree, a HEAD that is not
`origin/main` or a tag on another commit; `--github` also refuses when the
image was built from another commit than HEAD. `tests/test-release.sh` checks
this offline (R33 in `docs/testing.md`).
