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

# ── Smoke Test (real Atlassian instance) ─────────────────────────────────────
.PHONY: smoke-test
smoke-test: ## Smoke test against a real Atlassian instance (requires JIRA_URL, JIRA_USERNAME, JIRA_API_TOKEN)
ifndef CHART
	$(error CHART is required. Usage: make smoke-test CHART=atlassian)
endif
	@if ! kind get clusters 2>/dev/null | grep -q mcp-helm-test; then \
		echo "==> Creating kind cluster..."; \
		kind create cluster --name mcp-helm-test; \
	fi
	@echo "==> Creating test credentials secret..."
	kubectl create namespace mcp-test --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret generic atlassian-smoke-creds \
		--namespace mcp-test \
		--from-literal=JIRA_USERNAME=$${JIRA_USERNAME} \
		--from-literal=JIRA_API_TOKEN=$${JIRA_API_TOKEN} \
		--from-literal=CONFLUENCE_USERNAME=$${CONFLUENCE_USERNAME:-$$JIRA_USERNAME} \
		--from-literal=CONFLUENCE_API_TOKEN=$${CONFLUENCE_API_TOKEN:-$$JIRA_API_TOKEN} \
		--dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install smoke-$(CHART) charts/$(CHART) \
		--namespace mcp-test \
		--set config.jiraURL=$${JIRA_URL} \
		--set config.confluenceURL=$${CONFLUENCE_URL:-$$JIRA_URL/wiki} \
		--set secrets.existingSecret=atlassian-smoke-creds \
		--wait --timeout 120s
	@echo "==> Smoke test: verifying pod is ready..."
	kubectl wait --for=condition=ready pod \
		-l app.kubernetes.io/instance=smoke-$(CHART) \
		--namespace mcp-test --timeout=90s
	@echo "==> Smoke test passed — pod is running and ready"

# ── CI ───────────────────────────────────────────────────────────────────────
.PHONY: ci
ci: lint test ## Run lint + unit tests (CI shortcut)

# ── Help ─────────────────────────────────────────────────────────────────────
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
