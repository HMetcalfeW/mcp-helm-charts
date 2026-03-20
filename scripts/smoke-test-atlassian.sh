#!/usr/bin/env bash
#
# smoke-test-atlassian.sh — Smoke test for the Atlassian MCP Helm chart.
#
# Installs the chart into a kind cluster with real Atlassian credentials,
# waits for readiness, and verifies the MCP server endpoint responds.
#
# Required environment variables:
#   JIRA_URL              Jira instance URL
#   JIRA_USERNAME         Jira username (email for Cloud)
#   JIRA_API_TOKEN        Jira API token
#
# Optional:
#   CONFLUENCE_URL        Confluence URL (defaults to $JIRA_URL/wiki)
#   CONFLUENCE_USERNAME   Confluence username (defaults to $JIRA_USERNAME)
#   CONFLUENCE_API_TOKEN  Confluence API token (defaults to $JIRA_API_TOKEN)
#
# Usage:
#   ./scripts/smoke-test-atlassian.sh
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

CHART="atlassian"
NAMESPACE="mcp-smoke"
RELEASE="smoke-${CHART}"
SECRET_NAME="${RELEASE}-creds"

# ── Setup ──────────────────────────────────────────────────────────────────────
load_env
require_commands kind kubectl helm curl
require_env JIRA_URL JIRA_USERNAME JIRA_API_TOKEN

trap 'cleanup_release "$RELEASE" "$NAMESPACE" "$SECRET_NAME"' EXIT

# ── Cluster + credentials ─────────────────────────────────────────────────────
ensure_kind_cluster
ensure_namespace "$NAMESPACE"

info "Creating credentials secret..."
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=JIRA_USERNAME="${JIRA_USERNAME}" \
  --from-literal=JIRA_API_TOKEN="${JIRA_API_TOKEN}" \
  --from-literal=CONFLUENCE_USERNAME="${CONFLUENCE_USERNAME:-$JIRA_USERNAME}" \
  --from-literal=CONFLUENCE_API_TOKEN="${CONFLUENCE_API_TOKEN:-$JIRA_API_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

# ── Install ────────────────────────────────────────────────────────────────────
helm_install "$RELEASE" "charts/${CHART}" "$NAMESPACE" 120 \
  --set "secrets.existingSecret=${SECRET_NAME}" \
  --set "config.jiraURL=${JIRA_URL}" \
  --set "config.confluenceURL=${CONFLUENCE_URL:-${JIRA_URL}/wiki}"

# ── Verify ─────────────────────────────────────────────────────────────────────
POD_NAME=$(wait_for_ready_pod "app.kubernetes.io/instance=${RELEASE}" "$NAMESPACE")
info "Pod ${POD_NAME} is ready"

HTTP_CODE=$(verify_endpoint "$POD_NAME" "$NAMESPACE" 8080 "/sse")

# ── Report ─────────────────────────────────────────────────────────────────────
echo ""
info "Smoke test PASSED"
echo "  Chart:     ${CHART}"
echo "  Release:   ${RELEASE}"
echo "  Pod:       ${POD_NAME}"
echo "  Endpoint:  HTTP ${HTTP_CODE}"
echo ""
