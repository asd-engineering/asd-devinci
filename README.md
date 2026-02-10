# DevInCi - Dev in CI

Full development environment inside CI/CD runners with web terminal, VS Code, tunnels, and complete ASD CLI access. Just click the URL to connect - no SSH keys required.

*DevInCi (Dev in CI) by ASD (Accelerated Software Development B.V.)*

## Features

- **Web Terminal (ttyd)**: Full terminal in your browser
- **VS Code (code-server)**: VS Code IDE in your browser
- **Cloud Tunnel**: Instant public URL with embedded credentials
- **Full ASD CLI**: All commands available (`asd net`, `asd caddy`, `asd expose`, etc.)
- **Two Auth Modes**: API key (recommended) or ephemeral tokens
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
| `tunnel-host` | Tunnel server hostname | `cicd.eu1.asd.engineer` |
| `tunnel-port` | Tunnel server SSH port | `2223` |
| `ttl-minutes` | Token TTL (5-60, API key mode only) | `15` |
| `asd-version` | ASD CLI release tag | `latest` |
| `api-endpoint` | ASD API endpoint | `https://api.asd.host` |
| `keep-alive` | Keep session alive after setup | `false` |

## Outputs

| Output | Description |
|--------|-------------|
| `url` | Session URL with embedded credentials |
| `url-base` | Session URL without credentials |
| `tunnel-user` | Tunnel client ID |
| `local-port` | Local service port |
| `expires-at` | Token expiration (ISO 8601) |

## Available in Session

Once connected, you have access to:

- **Full ASD CLI**: `asd net`, `asd caddy`, `asd expose`, `asd ttyd`, `asd code`
- **Network Management**: Configure and manage services
- **Tunnel Control**: Create additional tunnels on the fly
- **All Development Tools**: Whatever you've installed on the runner

## Authentication Modes

### API Key Mode (Recommended)

Use an API key with `cicd:provision` scope for production workflows:

1. Create an API key at [asd.engineering/account/api-keys](https://asd.engineering/account/api-keys)
2. Enable the `cicd:provision` scope
3. Add to GitHub secrets as `ASD_API_KEY`

Benefits:
- Longer TTL (up to 60 minutes)
- Project binding for audit trails
- No rate limits

### Ephemeral Mode

For quick debugging without setup, ephemeral mode works without any API key:

```yaml
- uses: asd-engineering/asd-devinci@v1
```

Limitations:
- Shorter TTL (default 15 minutes)
- Rate limited (10 tokens/hour per IP)
- Limited features

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
          keep-alive: true

      - name: Keep alive for debugging
        if: steps.tests.outcome == 'failure'
        run: |
          echo "Debug session available for 6 hours"
          sleep 21600
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
          keep-alive: true
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
- Tokens are short-lived (configurable TTL)
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
.github/actions/devinci/tests/integration/prod-api.test.sh
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

This action is automatically published to [asd-engineering/asd-devinci](https://github.com/asd-engineering/asd-devinci) on every ASD CLI release. Use `@v1` for the latest stable version:

```yaml
- uses: asd-engineering/asd-devinci@v1
```

Development source lives in `asd-engineering/.asd/.github/actions/devinci/`.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- [ASD Engineering](https://asd.engineering)
- [Documentation](https://asd.engineering/docs)
- [API Key Management](https://asd.engineering/account/api-keys)
