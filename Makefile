CHART ?=

# ── Lint ─────────────────────────────────────────────────────────────────────
.PHONY: lint
lint: ## Lint all charts (or one: make lint CHART=atlassian)
ifdef CHART
	helm lint charts/$(CHART)
else
	@for chart in charts/*/; do \
		echo "==> Linting $$chart"; \
		helm lint "$$chart" || exit 1; \
	done
endif

# ── Template ─────────────────────────────────────────────────────────────────
.PHONY: template
template: ## Render templates (make template CHART=atlassian)
ifndef CHART
	$(error CHART is required. Usage: make template CHART=atlassian)
endif
	helm template test charts/$(CHART)

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

# ── Help ─────────────────────────────────────────────────────────────────────
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
