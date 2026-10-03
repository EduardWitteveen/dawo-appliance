# Contributing

Thank you for helping. This repository is an **experimental, unofficial** demonstrator (see [README.md](./README.md) and [GOVERNANCE.md](./GOVERNANCE.md)). Conversation may be in Dutch; technical content (code, Nix modules, tests, ADRs) is in **English**, documents for municipalities and end users are in **Dutch**.

*Nederlands, kort:* meld een issue, werk op een branch vanaf `main`, open een pull request die naar het issue verwijst, en laat iemand anders reviewen. Technische inhoud in het Engels, documentatie voor gemeenten in het Nederlands.

## How we work

1. **Issue first.** Search the [open issues and pull requests](https://github.com/EduardWitteveen/dawo-appliance/issues) and comment on the issue you pick up. Bugs, wishes and questions all start as an issue; security problems do not, see [SECURITY.md](./SECURITY.md).
2. **Branch from an up-to-date `main`:** `git fetch && git switch -c <type>/<issue>-<slug> origin/main` (e.g. `fix/176-guest-cet`).
3. **Commits:** [Conventional Commits](https://www.conventionalcommits.org/), English, in logical steps. No secrets, ever: passwords and keys are generated at install time.
4. **Pull request:** reference the issue (`Closes #N`), say what changed and paste the checks you ran. Keep it small.
5. **Review and merge:** preferably reviewed by another party. Changes to what the KVM boot tests exercise (host modules, guest, `vm/`, flake tests) are merged only after a green KVM run, label `needs-kvm`. Merges are rebase merges.

## Rules that matter here

- **Pin everything** (manifest, `flake.lock`, image digests); no `latest` or floating tags.
- **Upstream stays upstream:** consume DAWO-Core and mijn-bureau-infra by pinned revision; record every deviation in [`docs/deviations.md`](./docs/deviations.md) in the same pull request. Upstream bugs are tracked here with the label `upstream`.
- **Non-destructive by default:** code that can write a disk needs an explicit target and an explicit confirmation flag; the default is a dry run.
- **Stay in scope:** [ADR 0001](./docs/adr/0001-project-scope.md) and the [roadmap](./docs/roadmap.md).
- **Tests first:** a bug becomes a check. Never claim a check passed without running it.

## Checks

- `make check` (lint + offline tests; no Nix, no root) also runs in CI on every pull request.
- With Linux + Nix + KVM: `bash scripts/verify.sh` and the boot tests in [`docs/testing.md`](./docs/testing.md). Setup: [`docs/development.md`](./docs/development.md), [`docs/nix-setup.md`](./docs/nix-setup.md).

## AI assistants

AI coding assistants work under [AGENTS.md](./AGENTS.md) and [ADR 0005](./docs/adr/0005-ai-agent-conduct.md). A human maintainer stays responsible for what is merged.

## Code of conduct

Everyone taking part follows the [code of conduct](./CODE_OF_CONDUCT.md).
