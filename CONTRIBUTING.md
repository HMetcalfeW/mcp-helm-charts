# Contributing

Thank you for your interest in contributing to MCP Helm Charts.

## Publishing

Charts are published automatically via [chart-releaser-action](https://github.com/helm/chart-releaser-action) on merge to `main`. The Helm repository is hosted on GitHub Pages:

```bash
helm repo add mcp-helm-charts https://hmetcalfew.github.io/mcp-helm-charts
helm repo update
helm search repo mcp-helm-charts
```

## Adding a new chart

### 1. Scaffold the chart directory

```
charts/<chart-name>/
├── Chart.yaml
├── README.md
├── values.yaml
├── values.schema.json
├── .helmignore
├── ci/
│   └── install-values.yaml      # values for ct install (kind, no real creds)
├── templates/
│   ├── _helpers.tpl
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── secret.yaml
│   ├── configmap.yaml
│   ├── serviceaccount.yaml
│   └── NOTES.txt
└── tests/                       # helm-unittest suites
    ├── deployment_test.yaml
    ├── service_test.yaml
    ├── secret_test.yaml
    ├── configmap_test.yaml
    ├── serviceaccount_test.yaml
    └── notes_test.yaml
```

Use an existing chart (e.g., `charts/atlassian/`) as a reference.

### 2. Chart conventions

- **Security first** — `runAsNonRoot`, drop all capabilities, `readOnlyRootFilesystem` with explicit `emptyDir` mounts where writes are needed.
- **Secrets via Kubernetes Secret** — credentials are never stored in ConfigMaps. Support both inline values and `existingSecret`.
- **TCP probes** — most MCP servers don't expose HTTP health endpoints. Use `tcpSocket` probes on a named port.
- **Configurable transport** — support SSE and Streamable HTTP where the upstream image allows it.
- **Minimal defaults** — single replica, `ClusterIP` service, no ingress by default.
- **Official images only** — use the official Docker Hub image (e.g., `mcp/<chart-name>`). Do not fabricate version pins from unrelated sources.

### 3. Testing requirements

Every chart must have:

| Layer | Tool | What it covers |
|-------|------|----------------|
| Lint | `helm lint`, `shellcheck` | Template syntax, script correctness |
| Unit | `helm-unittest` | Template rendering for all value combinations |
| Install | `ct install` with `ci/install-values.yaml` | Deploys into kind with no real credentials |
| Smoke | `scripts/smoke-test-<chart>.sh` | End-to-end with real upstream credentials |

Run locally:

```bash
make lint                          # Helm lint + shellcheck
make test CHART=<chart-name>       # Unit tests
make kind-test CHART=<chart-name>  # Install into kind
make smoke-test CHART=<chart-name> # E2E with real credentials (requires .env)
```

### 4. Naming conventions

This repo will hold many charts. All names must be **chart-scoped** so it's clear what each file belongs to:

- Scripts: `scripts/smoke-test-<chart>.sh` (not `smoke-test.sh`)
- CI workflows: `.github/workflows/smoke-test-<chart>.yaml` (not `smoke-test.yaml`)
- Shared helpers: `scripts/test-helpers.sh` (truly shared logic only)

### 5. CI workflows

When adding a chart, create a chart-specific smoke test workflow:

```
.github/workflows/smoke-test-<chart>.yaml
```

The generic workflows (`lint-test.yaml`, `release.yaml`) apply to all charts automatically.

### 6. Smoke test credentials

For local smoke testing, create a `.env` file (git-ignored) with the required environment variables. See `.env.example` for the template.

Do **not** commit credentials. CI smoke tests pull secrets from GitHub Actions secrets.

### 7. Pull request checklist

See the [PR template](.github/PULL_REQUEST_TEMPLATE.md) for the full checklist. At minimum:

- `make lint` passes
- `make test CHART=<chart>` passes
- `make template CHART=<chart>` renders without errors
- Chart version bumped in `Chart.yaml`
- `values.schema.json` covers all values
- Unit tests cover all templates

## Development prerequisites

- [Helm](https://helm.sh/docs/intro/install/) v3.17+
- [helm-unittest](https://github.com/helm-unittest/helm-unittest) plugin
- [shellcheck](https://www.shellcheck.net/)
- [kind](https://kind.sigs.k8s.io/) (for install and smoke tests)
- [chart-testing (ct)](https://github.com/helm/chart-testing) (optional, used in CI)
