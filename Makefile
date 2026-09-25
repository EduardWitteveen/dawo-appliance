# dawo-appliance — local development targets (docs/development.md).
# The default gate (`make check`) needs no Nix and no root; `verify`,
# `speed-check` and `screenshots` need Linux + Nix (+ KVM). Scripts are invoked
# via `bash` so the executable bit does not matter (Windows checkouts,
# core.filemode=false).

SHELL := bash
BOOTSTRAP := installer/bootstrap/dawo-appliance-bootstrap
MANIFEST  := manifest/appliance-manifest.json
SHA_FILE  := manifest/appliance-manifest.json.sha256
SHELL_SCRIPTS := $(BOOTSTRAP) tests/test-bootstrap-dryrun.sh tests/test-k3s-install.sh tests/test-image-digests.sh tests/test-health-check.sh k8s/bootstrap/install-k3s.sh scripts/status.sh scripts/verify.sh scripts/screenshots.sh scripts/speed-check.sh scripts/check-upstream.sh scripts/resolve-image-digests.sh health/dawo-appliance-health.sh health/dawo-appliance-open-dashboard.sh apps/mijn-bureau/deploy.sh

.DEFAULT_GOAL := check

.PHONY: help
help:
	@echo "dawo-appliance make targets:"
	@echo "  make status        session orientation: where were we + live checks"
	@echo "  make verify        full verification suite (Linux + Nix + KVM; see docs/testing.md)"
	@echo "  make screenshots   refresh docs/screenshots from the boot tests (Linux + Nix + KVM)"
	@echo "  make speed-check   is this machine set up for fast builds/VM tests? (APPLY=1 to fix)"
	@echo "  make check         lint + test (default local gate)"
	@echo "  make test          run the offline test suites (bootstrap dry-run, k3s installer)"
	@echo "  make plan          run the bootstrap dry-run against the local manifest"
	@echo "  make verify-manifest  bootstrap 'verify' only: local manifest checksum"
	@echo "  make manifest-sum  regenerate $(SHA_FILE)"
	@echo "  make lint          shellcheck the shell scripts"
	@echo "  make fmt           format shell scripts with shfmt (if installed)"
	@echo "  make fmt-check     check shell formatting without writing"

.PHONY: status
status:
	bash scripts/status.sh

.PHONY: verify
verify:
	bash scripts/verify.sh

.PHONY: speed-check
speed-check:
	bash scripts/speed-check.sh

.PHONY: screenshots
screenshots:
	bash scripts/screenshots.sh

.PHONY: check
check: lint test

.PHONY: test
test:
	bash tests/test-bootstrap-dryrun.sh
	bash tests/test-k3s-install.sh
	bash tests/test-image-digests.sh
	bash tests/test-health-check.sh

.PHONY: plan
plan:
	bash $(BOOTSTRAP) plan --offline --manifest-url "file://$(CURDIR)/$(MANIFEST)"

.PHONY: verify-manifest
verify-manifest:
	bash $(BOOTSTRAP) verify --offline --manifest-url "file://$(CURDIR)/$(MANIFEST)"

.PHONY: manifest-sum
manifest-sum:
	cd manifest && sha256sum appliance-manifest.json > appliance-manifest.json.sha256
	@echo "wrote $(SHA_FILE)"

.PHONY: lint
lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SHELL_SCRIPTS) && echo "shellcheck: OK"; \
	else \
		echo "shellcheck not installed — skipping (install it for linting)"; \
	fi

.PHONY: fmt
fmt:
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -w -i 2 -ci $(SHELL_SCRIPTS) && echo "shfmt: formatted"; \
	else \
		echo "shfmt not installed — skipping"; \
	fi

.PHONY: fmt-check
fmt-check:
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -d -i 2 -ci $(SHELL_SCRIPTS); \
	else \
		echo "shfmt not installed — skipping"; \
	fi
