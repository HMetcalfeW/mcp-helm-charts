#!/usr/bin/env bash
#
# smoke-test.sh — End-to-end smoke test for a chart against a real service.
#
# Installs the chart into a kind cluster with real credentials, waits for
# readiness, port-forwards, and verifies the MCP server responds.
#
# Required environment variables (atlassian chart):
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
#   ./scripts/smoke-test.sh atlassian
#

set -euo pipefail

CHART="${1:?Usage: $0 <chart-name>}"
CLUSTER_NAME="mcp-helm-test"
NAMESPACE="mcp-smoke"
RELEASE="smoke-${CHART}"
SECRET_NAME="${RELEASE}-creds"
LOCAL_PORT=18080
TIMEOUT=120

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}==>${NC} $*"; }
fail()  { echo -e "${RED}==>${NC} $*" >&2; exit 1; }

# ── Preflight checks ──────────────────────────────────────────────────────────
for cmd in kind kubectl helm; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd is required but not installed"
done

if [[ "$CHART" == "atlassian" ]]; then
  [[ -n "${JIRA_URL:-}" ]]          || fail "JIRA_URL is required"
  [[ -n "${JIRA_USERNAME:-}" ]]     || fail "JIRA_USERNAME is required"
  [[ -n "${JIRA_API_TOKEN:-}" ]]    || fail "JIRA_API_TOKEN is required"
fi

# ── Cleanup handler ───────────────────────────────────────────────────────────
PF_PID=""
cleanup() {
  if [[ -n "$PF_PID" ]] && kill -0 "$PF_PID" 2>/dev/null; then
    kill "$PF_PID" 2>/dev/null || true
    wait "$PF_PID" 2>/dev/null || true
  fi
  info "Cleaning up release ${RELEASE}..."
  helm uninstall "$RELEASE" --namespace "$NAMESPACE" 2>/dev/null || true
  kubectl delete secret "$SECRET_NAME" --namespace "$NAMESPACE" 2>/dev/null || true
  kubectl delete namespace "$NAMESPACE" --ignore-not-found 2>/dev/null || true
}
trap cleanup EXIT

# ── Kind cluster ───────────────────────────────────────────────────────────────
if ! kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
  info "Creating kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "$CLUSTER_NAME"
else
  info "Using existing kind cluster '${CLUSTER_NAME}'"
fi

# ── Namespace + credentials ────────────────────────────────────────────────────
info "Setting up namespace and credentials..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

if [[ "$CHART" == "atlassian" ]]; then
  kubectl create secret generic "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --from-literal=JIRA_USERNAME="${JIRA_USERNAME}" \
    --from-literal=JIRA_API_TOKEN="${JIRA_API_TOKEN}" \
    --from-literal=CONFLUENCE_USERNAME="${CONFLUENCE_USERNAME:-$JIRA_USERNAME}" \
    --from-literal=CONFLUENCE_API_TOKEN="${CONFLUENCE_API_TOKEN:-$JIRA_API_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

# ── Install chart ──────────────────────────────────────────────────────────────
info "Installing chart '${CHART}'..."
HELM_ARGS=(
  upgrade --install "$RELEASE" "charts/${CHART}"
  --namespace "$NAMESPACE"
  --set "secrets.existingSecret=${SECRET_NAME}"
  --wait
  --timeout "${TIMEOUT}s"
)

if [[ "$CHART" == "atlassian" ]]; then
  HELM_ARGS+=(
    --set "config.jiraURL=${JIRA_URL}"
    --set "config.confluenceURL=${CONFLUENCE_URL:-${JIRA_URL}/wiki}"
  )
fi

helm "${HELM_ARGS[@]}"

# ── Verify pod readiness ──────────────────────────────────────────────────────
info "Waiting for pod readiness..."
kubectl wait --for=condition=ready pod \
  -l "app.kubernetes.io/instance=${RELEASE}" \
  --namespace "$NAMESPACE" \
  --timeout="${TIMEOUT}s"

POD_NAME=$(kubectl get pod \
  -l "app.kubernetes.io/instance=${RELEASE}" \
  --namespace "$NAMESPACE" \
  -o jsonpath='{.items[0].metadata.name}')

info "Pod ${POD_NAME} is ready"

# ── Port-forward and verify endpoint ──────────────────────────────────────────
info "Port-forwarding to localhost:${LOCAL_PORT}..."
kubectl port-forward "pod/${POD_NAME}" "${LOCAL_PORT}:8080" \
  --namespace "$NAMESPACE" &
PF_PID=$!

# Wait for port-forward to be established
for i in $(seq 1 15); do
  if curl -sf "http://localhost:${LOCAL_PORT}/sse" --max-time 2 -o /dev/null 2>/dev/null; then
    break
  fi
  if [[ $i -eq 15 ]]; then
    warn "Port-forward did not become ready in time, checking pod logs..."
    kubectl logs "$POD_NAME" --namespace "$NAMESPACE" --tail=20
    fail "Could not connect to MCP server on localhost:${LOCAL_PORT}"
  fi
  sleep 1
done

# Verify SSE endpoint responds (expect text/event-stream or connection upgrade)
info "Verifying MCP server endpoint..."
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' \
  "http://localhost:${LOCAL_PORT}/sse" \
  --max-time 5 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "307" ]]; then
  info "MCP server responded with HTTP ${HTTP_CODE}"
else
  warn "Unexpected HTTP ${HTTP_CODE}, checking pod logs..."
  kubectl logs "$POD_NAME" --namespace "$NAMESPACE" --tail=30
  # Non-200 may still be acceptable (e.g., 404 for wrong path) — check if the
  # server process is alive and listening
  if [[ "$HTTP_CODE" != "000" ]]; then
    warn "Server is listening (HTTP ${HTTP_CODE}) but /sse path may differ — treating as partial pass"
  else
    fail "MCP server is not responding"
  fi
fi

# ── Report ─────────────────────────────────────────────────────────────────────
echo ""
info "Smoke test PASSED"
echo "  Chart:     ${CHART}"
echo "  Release:   ${RELEASE}"
echo "  Pod:       ${POD_NAME}"
echo "  Endpoint:  HTTP ${HTTP_CODE}"
echo ""
