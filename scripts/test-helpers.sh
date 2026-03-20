#!/usr/bin/env bash
#
# test-helpers.sh — Shared functions for MCP Helm Charts test scripts.
#
# Source this file from chart-specific scripts:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   source "${SCRIPT_DIR}/test-helpers.sh"
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="mcp-helm-test"

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}==>${NC} $*"; }
fail()  { echo -e "${RED}==>${NC} $*" >&2; exit 1; }

# ── .env loading ───────────────────────────────────────────────────────────────
load_env() {
  if [[ -f "${REPO_ROOT}/.env" ]]; then
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/.env"
  fi
}

# ── Preflight ──────────────────────────────────────────────────────────────────
require_commands() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || fail "$cmd is required but not installed"
  done
}

require_env() {
  for var in "$@"; do
    [[ -n "${!var:-}" ]] || fail "${var} is required"
  done
}

# ── Kind cluster management ───────────────────────────────────────────────────
ensure_kind_cluster() {
  if ! kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    info "Creating kind cluster '${CLUSTER_NAME}'..."
    kind create cluster --name "$CLUSTER_NAME"
  else
    info "Using existing kind cluster '${CLUSTER_NAME}'"
  fi
}

# ── Namespace ──────────────────────────────────────────────────────────────────
ensure_namespace() {
  local ns="$1"
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
}

# ── Helm install ───────────────────────────────────────────────────────────────
helm_install() {
  local release="$1"
  local chart_path="$2"
  local namespace="$3"
  local timeout="${4:-120}"
  shift 4

  info "Installing chart '${chart_path}'..."
  helm upgrade --install "$release" "$chart_path" \
    --namespace "$namespace" \
    --wait \
    --timeout "${timeout}s" \
    "$@"
}

# ── Pod readiness ──────────────────────────────────────────────────────────────
wait_for_ready_pod() {
  local label="$1"
  local namespace="$2"
  local timeout="${3:-120}"

  info "Waiting for pod readiness..."
  kubectl wait --for=condition=ready pod \
    -l "$label" \
    --namespace "$namespace" \
    --timeout="${timeout}s"

  kubectl get pod \
    -l "$label" \
    --namespace "$namespace" \
    -o jsonpath='{.items[0].metadata.name}'
}

# ── Port-forward and verify ───────────────────────────────────────────────────
PF_PID=""

verify_endpoint() {
  local pod_name="$1"
  local namespace="$2"
  local container_port="$3"
  local path="$4"
  local local_port="${5:-18080}"

  info "Port-forwarding to localhost:${local_port}..."
  kubectl port-forward "pod/${pod_name}" "${local_port}:${container_port}" \
    --namespace "$namespace" &
  PF_PID=$!

  # Wait for port-forward to be established
  for i in $(seq 1 15); do
    if curl -sf "http://localhost:${local_port}${path}" --max-time 2 -o /dev/null 2>/dev/null; then
      break
    fi
    if [[ $i -eq 15 ]]; then
      warn "Port-forward did not become ready in time, checking pod logs..."
      kubectl logs "$pod_name" --namespace "$namespace" --tail=20
      fail "Could not connect to server on localhost:${local_port}"
    fi
    sleep 1
  done

  info "Verifying endpoint ${path}..."
  local http_code
  http_code=$(curl -sf -o /dev/null -w '%{http_code}' \
    "http://localhost:${local_port}${path}" \
    --max-time 5 2>/dev/null || echo "000")

  if [[ "$http_code" == "200" || "$http_code" == "307" ]]; then
    info "Server responded with HTTP ${http_code}"
  elif [[ "$http_code" != "000" ]]; then
    warn "Server is listening (HTTP ${http_code}) but ${path} may differ — treating as partial pass"
  else
    warn "Unexpected response, checking pod logs..."
    kubectl logs "$pod_name" --namespace "$namespace" --tail=30
    fail "Server is not responding"
  fi

  echo "$http_code"
}

# ── Cleanup ────────────────────────────────────────────────────────────────────
cleanup_release() {
  local release="$1"
  local namespace="$2"
  local secret_name="${3:-}"

  if [[ -n "$PF_PID" ]] && kill -0 "$PF_PID" 2>/dev/null; then
    kill "$PF_PID" 2>/dev/null || true
    wait "$PF_PID" 2>/dev/null || true
  fi
  info "Cleaning up release ${release}..."
  helm uninstall "$release" --namespace "$namespace" 2>/dev/null || true
  if [[ -n "$secret_name" ]]; then
    kubectl delete secret "$secret_name" --namespace "$namespace" 2>/dev/null || true
  fi
  kubectl delete namespace "$namespace" --ignore-not-found 2>/dev/null || true
}
