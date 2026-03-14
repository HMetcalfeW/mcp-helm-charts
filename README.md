# MCP Helm Charts

Production-ready Helm charts for deploying [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) servers on Kubernetes.

## Available Charts

| Chart | Description | Docker Image |
|-------|-------------|-------------|
| [atlassian](charts/atlassian/) | Jira and Confluence access | [`mcp/atlassian`](https://hub.docker.com/r/mcp/atlassian) |

See [ROADMAP.md](ROADMAP.md) for upcoming charts.

## Usage

```bash
helm repo add mcp-helm-charts https://hmetcalfew.github.io/mcp-helm-charts
helm repo update
helm search repo mcp-helm-charts
```

Then install a chart:

```bash
helm install my-release mcp-helm-charts/<chart-name> -f values.yaml
```

## Chart Conventions

All charts in this repo follow a consistent structure:

- **Security first** — non-root, drop all capabilities, read-only where possible
- **Read-only by default** — write operations disabled unless explicitly enabled
- **TCP probes** — most MCP servers (FastMCP, etc.) don't expose HTTP health endpoints
- **Secrets via k8s Secret** — credentials are never baked into ConfigMaps
- **Configurable transport** — SSE or Streamable HTTP where the image supports it
- **Minimal footprint** — single replica, ClusterIP service, no ingress by default

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for chart conventions, testing requirements, and how to add a new chart.

Check the [ROADMAP.md](ROADMAP.md) for charts we're looking for.

## Development

```bash
# Lint all charts
make lint

# Render templates for a chart
make template CHART=atlassian

# Run integration tests (requires kind)
make kind-test CHART=atlassian
```

## License

[Apache 2.0](LICENSE)
