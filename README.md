# MCP Helm Charts

Production-ready Helm charts for deploying [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) servers on Kubernetes.

## Available Charts

| Chart | Description | Mode |
|-------|-------------|------|
| [mcp-server](charts/mcp-server/) | Generic chart for any MCP server | Supergateway (stdio) or Native (HTTP) |
| [atlassian](charts/atlassian/) | Jira, Confluence, and Teamwork Graph | Native |

See [ROADMAP.md](ROADMAP.md) for upcoming charts.

## Quick Start

```bash
helm repo add mcp-helm-charts https://hmetcalfew.github.io/mcp-helm-charts
helm repo update
```

### Deploy a stdio MCP server (supergateway mode)

Wraps any stdio-based MCP server and exposes it over Streamable HTTP:

```bash
helm install aws-docs mcp-helm-charts/mcp-server \
  --set command="uvx awslabs.aws-documentation-mcp-server@latest"
```

### Deploy a native HTTP MCP server

For servers that speak HTTP directly (FastMCP, Go SDK, etc.):

```bash
helm install my-server mcp-helm-charts/mcp-server \
  --set mode=native \
  --set image.repository=my-org/my-mcp-server \
  --set image.tag=latest \
  --set nativeCommand[0]=mcp \
  --set nativeArgs[0]=run \
  --set nativeArgs[1]=--port \
  --set nativeArgs[2]=8000
```

### Deploy Atlassian MCP

```bash
helm install atlassian mcp-helm-charts/atlassian \
  --set secrets.atlassianApiKey=<your-key>
```

## Chart Conventions

All charts in this repo follow a consistent structure:

- **Security first** — non-root, drop all capabilities, read-only root filesystem
- **Read-only by default** — write operations disabled unless explicitly enabled
- **Health probes** — HTTP health checks on configurable endpoints
- **Secrets via k8s Secret** — credentials are never baked into ConfigMaps
- **Configurable transport** — Streamable HTTP or SSE where supported
- **Minimal footprint** — single replica, ClusterIP service, no ingress by default

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for chart conventions, testing requirements, and how to add a new chart.

Check the [ROADMAP.md](ROADMAP.md) for charts we're looking for.

## Development

```bash
# Lint all charts
make lint

# Render templates for a chart
make template CHART=mcp-server

# Run integration tests (requires kind)
make kind-test CHART=atlassian
```

## License

[Apache 2.0](LICENSE)
