CHART ?=

# ── Lint ─────────────────────────────────────────────────────────────────────
.PHONY: lint
lint: lint-charts lint-scripts ## Lint charts and scripts

.PHONY: lint-charts
lint-charts: ## Lint all Helm charts (or one: make lint-charts CHART=atlassian)
ifdef CHART
	helm lint charts/$(CHART)
else
	@for chart in charts/*/; do \
		echo "==> Linting $$chart"; \
		helm lint "$$chart" || exit 1; \
	done
endif

.PHONY: lint-scripts
lint-scripts: ## Lint shell scripts with shellcheck
	@echo "==> Running shellcheck..."
	shellcheck -x -P scripts scripts/*.sh

# ── Template ─────────────────────────────────────────────────────────────────
.PHONY: template
template: ## Render templates (make template CHART=atlassian)
ifndef CHART
	$(error CHART is required. Usage: make template CHART=atlassian)
endif
	helm template test charts/$(CHART)

# ── Unit Tests ───────────────────────────────────────────────────────────────
.PHONY: test
test: ## Run helm-unittest (all charts or one: make test CHART=atlassian)
ifdef CHART
	helm unittest charts/$(CHART)
else
	@for chart in charts/*/; do \
		if [ -d "$$chart/tests" ]; then \
			echo "==> Testing $$chart"; \
			helm unittest "$$chart" || exit 1; \
		fi; \
	done
endif

# ── CT Lint (chart-testing) ──────────────────────────────────────────────────
.PHONY: ct-lint
ct-lint: ## Run chart-testing lint against changed charts
	ct lint --config ct.yaml

# ── Kind Test ────────────────────────────────────────────────────────────────
.PHONY: kind-test
kind-test: ## Install chart into kind cluster (make kind-test CHART=atlassian)
ifndef CHART
	$(error CHART is required. Usage: make kind-test CHART=atlassian)
endif
	@if ! kind get clusters 2>/dev/null | grep -q mcp-helm-test; then \
		echo "==> Creating kind cluster..."; \
		kind create cluster --name mcp-helm-test; \
	fi
	helm upgrade --install test-$(CHART) charts/$(CHART) \
		--namespace mcp-test --create-namespace \
		--wait --timeout 120s
	@echo "==> Chart $(CHART) installed successfully"

.PHONY: kind-teardown
kind-teardown: ## Delete kind test cluster
	kind delete cluster --name mcp-helm-test

# ── Smoke Test ───────────────────────────────────────────────────────────────
.PHONY: smoke-test
smoke-test: ## Smoke test with real credentials (make smoke-test CHART=atlassian)
ifndef CHART
	$(error CHART is required. Usage: make smoke-test CHART=atlassian)
endif
	@test -x scripts/smoke-test-$(CHART).sh || \
		{ echo "Error: scripts/smoke-test-$(CHART).sh not found"; exit 1; }
	./scripts/smoke-test-$(CHART).sh

# ── CI ───────────────────────────────────────────────────────────────────────
.PHONY: ci
ci: lint test ## Run lint + unit tests (CI shortcut)

# ── Help ─────────────────────────────────────────────────────────────────────
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
