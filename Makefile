# dawo-appliance — local development targets.
# These targets need no Nix and no root. Scripts are invoked via `bash` because
# the working tree may live on a filesystem where the executable bit cannot be
# set (e.g. /mnt/c under WSL without metadata; see docs/open-questions.md OQ-1).

SHELL := bash
BOOTSTRAP := installer/bootstrap/dawo-appliance-bootstrap
MANIFEST  := manifest/appliance-manifest.json
SHA_FILE  := manifest/appliance-manifest.json.sha256
SHELL_SCRIPTS := $(BOOTSTRAP) tests/test-bootstrap-dryrun.sh scripts/status.sh

.DEFAULT_GOAL := check

.PHONY: help
help:
	@echo "dawo-appliance make targets:"
	@echo "  make status        session orientation: where were we + live checks"
	@echo "  make check         lint + test (default local gate)"
	@echo "  make test          run the bootstrap dry-run test suite"
	@echo "  make plan          run the bootstrap dry-run against the local manifest"
	@echo "  make verify        verify the local manifest checksum only"
	@echo "  make manifest-sum  regenerate $(SHA_FILE)"
	@echo "  make lint          shellcheck the shell scripts"
	@echo "  make fmt           format shell scripts with shfmt (if installed)"
	@echo "  make fmt-check     check shell formatting without writing"

.PHONY: status
status:
	bash scripts/status.sh

.PHONY: check
check: lint test

.PHONY: test
test:
	bash tests/test-bootstrap-dryrun.sh

.PHONY: plan
plan:
	bash $(BOOTSTRAP) plan --offline --manifest-url "file://$(CURDIR)/$(MANIFEST)"

.PHONY: verify
verify:
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
