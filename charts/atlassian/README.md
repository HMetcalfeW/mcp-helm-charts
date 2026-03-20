# Atlassian MCP Server

Helm chart for deploying the [Atlassian MCP server](https://github.com/sooperset/mcp-atlassian) on Kubernetes. Provides Jira and Confluence access via the Model Context Protocol.

Docker image: [`mcp/atlassian`](https://hub.docker.com/r/mcp/atlassian)

## Install

```bash
helm repo add mcp-helm-charts https://hmetcalfe.github.io/mcp-helm-charts
helm install atlassian mcp-helm-charts/atlassian \
  --set config.jiraURL=https://your-domain.atlassian.net \
  --set config.confluenceURL=https://your-domain.atlassian.net/wiki \
  --set secrets.jiraUsername=you@example.com \
  --set secrets.jiraToken=your-api-token \
  --set secrets.confluenceUsername=you@example.com \
  --set secrets.confluenceToken=your-api-token
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.name` | Docker image name | `mcp/atlassian` |
| `image.tag` | Docker image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `replicaCount` | Number of replicas | `1` |
| `server.transport` | MCP transport (`sse` or `streamable-http`) | `sse` |
| `server.port` | Server listen port | `8080` |
| `server.readOnly` | Disable write operations | `true` |
| `server.extraArgs` | Additional CLI flags | `[]` |
| `config.jiraURL` | Jira instance URL | `""` |
| `config.confluenceURL` | Confluence instance URL | `""` |
| `config.confluenceSpacesFilter` | Comma-separated space keys to filter | `""` |
| `config.jiraProjectsFilter` | Comma-separated project keys to filter | `""` |
| `secrets.existingSecret` | Name of pre-existing Secret (skips Secret creation) | `""` |
| `secrets.jiraUsername` | Jira username (email for Cloud) | `""` |
| `secrets.jiraToken` | Jira API token | `""` |
| `secrets.confluenceUsername` | Confluence username (email for Cloud) | `""` |
| `secrets.confluenceToken` | Confluence API token | `""` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `8080` |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `128Mi` |
| `resources.limits.cpu` | CPU limit | `500m` |
| `resources.limits.memory` | Memory limit | `512Mi` |
| `serviceAccount.create` | Create a service account | `true` |
| `podSecurityContext.runAsNonRoot` | Run as non-root | `true` |
| `securityContext.readOnlyRootFilesystem` | Read-only root filesystem | `true` |

## Using an Existing Secret

To use credentials managed externally (e.g., via External Secrets Operator or Sealed Secrets), first create the Secret:

```bash
kubectl create secret generic my-atlassian-credentials \
  --namespace <your-namespace> \
  --from-literal=JIRA_USERNAME=you@example.com \
  --from-literal=JIRA_API_TOKEN=your-jira-api-token \
  --from-literal=CONFLUENCE_USERNAME=you@example.com \
  --from-literal=CONFLUENCE_API_TOKEN=your-confluence-api-token
```

Then reference it in your values:

```yaml
secrets:
  existingSecret: my-atlassian-credentials
```

The referenced Secret must contain these keys: `JIRA_USERNAME`, `JIRA_API_TOKEN`, `CONFLUENCE_USERNAME`, `CONFLUENCE_API_TOKEN`.

## Authentication

The chart supports Atlassian Cloud authentication (username + API token). For Server/Data Center with Personal Access Tokens, use `server.extraArgs`:

```yaml
server:
  extraArgs:
    - "--jira-personal-token"
    - "your-pat"
```

## Notes

- The server runs in **read-only mode** by default. Set `server.readOnly: false` to enable write operations.
- Health probes use TCP socket checks since FastMCP does not expose HTTP health endpoints.
- The container runs with a **read-only root filesystem**. Writable paths (`/tmp`, `/home/app/.cache`) are mounted as `emptyDir` volumes.
- The container image runs as the `app` user; the pod security context overrides to UID 1001.
