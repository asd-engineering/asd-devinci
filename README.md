# DevInCi - Dev in CI

Full development environment inside CI/CD runners with web terminal, VS Code, tunnels, and complete ASD CLI access. Just click the URL to connect - no SSH keys required.

*DevInCi (Dev in CI) by ASD (Accelerated Software Development B.V.)*

## Features

- **Web Terminal (ttyd)**: Full terminal in your browser
- **VS Code (code-server)**: VS Code IDE in your browser
- **Cloud Tunnel**: Instant public URL with embedded credentials
- **Full ASD CLI**: All commands available (`asd net`, `asd caddy`, `asd expose`, etc.)
- **Three Auth Modes**: Pre-existing credentials, API key, or ephemeral tokens
- **Auto Server Discovery**: Tunnel host, port, and ownership fetched from API
- **Cross-Platform**: Works on Linux, macOS, and Windows runners
- **No SSH Keys**: Just click the URL to connect

## Quick Start

### Basic Usage (Ephemeral Mode)

```yaml
- uses: asd-engineering/asd-devinci@v1
  with:
    tunnel-name: debug-${{ github.run_id }}
```

### Production Usage (API Key Mode)

```yaml
- uses: asd-engineering/asd-devinci@v1
  with:
    api-key: ${{ secrets.ASD_API_KEY }}
    tunnel-name: debug-${{ github.run_id }}
    ttl-minutes: 15
```

### Pre-existing Credentials (from CLI)

```yaml
- uses: asd-engineering/asd-devinci@v1
  with:
    client-id: ${{ inputs.client-id }}
    client-secret: ${{ inputs.client-secret }}
    tunnel-host: ${{ inputs.tunnel-host }}
    tunnel-port: ${{ inputs.tunnel-port }}
```

### VS Code in Browser

```yaml
- uses: asd-engineering/asd-devinci@v1
  with:
    api-key: ${{ secrets.ASD_API_KEY }}
    interface: codeserver
    tunnel-name: vscode-${{ github.run_id }}
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `api-key` | ASD API key with `cicd:provision` scope | - |
| `interface` | Interface type: `ttyd` (terminal) or `codeserver` (VS Code) | `ttyd` |
| `shell` | Shell: `bash`, `zsh`, `powershell` | `bash` |
| `username` | Basic auth username | `asd` |
| `password` | Basic auth password (auto-generated if empty) | - |
| `tunnel-name` | Subdomain prefix | Short SHA |
| `tunnel-host` | Tunnel server hostname (auto-detected from API) | - |
| `tunnel-port` | Tunnel server SSH port (auto-detected from API) | - |
| `client-id` | Pre-existing ASD client ID (skips provisioning) | - |
| `client-secret` | Pre-existing ASD client secret | - |
| `direct` | Use `--direct` flag for asd expose | `false` |
| `ttl-minutes` | Token TTL in minutes (0 = no expiry, API key mode only) | `0` |
| `asd-version` | ASD CLI release tag | `latest` |
| `api-endpoint` | ASD API endpoint | `https://api.asd.host` |

## Outputs

| Output | Description |
|--------|-------------|
| `url` | Session URL with embedded credentials |
| `url-base` | Session URL without credentials |
| `tunnel-user` | Tunnel client ID |
| `local-port` | Local service port |
| `expires-at` | Token expiration (ISO 8601) |

## Authentication Modes

### 1. Pre-existing Credentials (Fastest)

When `client-id` and `client-secret` are provided, provisioning is skipped entirely. Requires `tunnel-host` and `tunnel-port` to be set explicitly. Used by `asd terminal` CLI which passes credentials from its local registry.

### 2. API Key Mode (Recommended)

Use an API key with `cicd:provision` scope. The API returns all server details (host, port, ownership) automatically.

1. Create an API key at [asd.host/workspace/api-keys](https://asd.host/workspace/api-keys)
2. Enable the `cicd:provision` scope
3. Add to GitHub secrets as `ASD_API_KEY`

### 3. Ephemeral Mode (No Setup)

For quick debugging without any configuration. Limited TTL and rate limited.

```yaml
- uses: asd-engineering/asd-devinci@v1
```

## Server Discovery

Tunnel server details are resolved automatically:

- **API key mode**: `credential-provision` returns `tunnel_host`, `tunnel_port`, `ownership_type`
- **Ephemeral mode**: `create-ephemeral-token` returns the same fields
- **Pre-existing**: Must provide `tunnel-host` and `tunnel-port` explicitly

URL construction adapts to ownership type:
- **Shared**: `https://{name}-{client-id}.{host}/`
- **Dedicated/Self-hosted**: `https://{name}.{host}/`

## Examples

### Debug a Failing Job

```yaml
name: Debug Workflow

on:
  workflow_dispatch:

jobs:
  debug:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run tests
        id: tests
        run: npm test
        continue-on-error: true

      - name: Start DevInCi on failure
        if: steps.tests.outcome == 'failure'
        uses: asd-engineering/asd-devinci@v1
        with:
          api-key: ${{ secrets.ASD_API_KEY }}
          tunnel-name: debug-${{ github.run_id }}
```

### Interactive Development with VS Code

```yaml
name: Development Environment

on:
  workflow_dispatch:
    inputs:
      ttl:
        description: 'Session duration (minutes)'
        default: '30'

jobs:
  dev:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup environment
        run: npm install

      - name: Start VS Code via DevInCi
        uses: asd-engineering/asd-devinci@v1
        with:
          api-key: ${{ secrets.ASD_API_KEY }}
          interface: codeserver
          tunnel-name: dev-${{ github.actor }}
          ttl-minutes: ${{ github.event.inputs.ttl }}
```

### Windows PowerShell Session

```yaml
- uses: asd-engineering/asd-devinci@v1
  with:
    shell: powershell
    tunnel-name: windows-debug
```

## Security

- Credentials are embedded in the URL for one-click access
- URLs use HTTPS with TLS encryption
- Tokens have configurable TTL (ephemeral mode uses short-lived tokens)
- Basic auth protects the endpoint
- All secrets are masked in logs

## Requirements

- GitHub Actions runner (ubuntu, macos, or windows)
- Internet access for tunnel connection
- Optional: ASD API key for production use

## Troubleshooting

### "Failed to provision credentials"

1. Check your API key has `cicd:provision` scope
2. Verify the key is not expired
3. Check rate limits (ephemeral mode)

### "Tunnel connection failed"

1. Verify firewall allows outbound SSH (port 2223)
2. Check the tunnel server is accessible
3. Try a different tunnel-host

### "Interface not accessible"

1. Wait a few seconds for initialization
2. Check the local-port output
3. Verify the interface started successfully

## Testing

### Run Integration Tests Locally

```bash
# Set API key (optional, some tests work without)
export ASD_TEST_API_KEY="your-key-here"

# Run tests against production API
tests/integration/prod-api.test.sh
```

### Trigger Test Workflow on GitHub

```bash
# Basic test (ephemeral mode only)
gh workflow run test-devinci.yml

# Full E2E tests (requires ASD_TEST_API_KEY secret)
gh workflow run test-devinci.yml -f run_e2e=true
```

### Required Secrets for Testing

| Secret | Description |
|--------|-------------|
| `ASD_TEST_API_KEY` | API key with `cicd:provision` scope |

## Release

Use `@v1` for the latest stable version:

```yaml
- uses: asd-engineering/asd-devinci@v1
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- [ASD](https://asd.host)
- [Documentation](https://asd.host/docs)
- [API Key Management](https://asd.host/workspace/api-keys)
