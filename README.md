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
- **Multi-CI**: Works on GitHub Actions and GitLab CI/CD
- **Cross-Platform**: Works on Linux, macOS, and Windows runners
- **No SSH Keys**: Just click the URL to connect

## Quick Start

### GitHub Actions

#### Basic Usage (Ephemeral Mode)

```yaml
- uses: asd-engineering/asd-devinci@v1
  with:
    tunnel-name: debug-${{ github.run_id }}
```

#### Production Usage (API Key Mode)

```yaml
- uses: asd-engineering/asd-devinci@v1
  with:
    api-key: ${{ secrets.ASD_API_KEY }}
    tunnel-name: debug-${{ github.run_id }}
    ttl-minutes: 15
```

#### Pre-existing Credentials (from CLI)

```yaml
- uses: asd-engineering/asd-devinci@v1
  with:
    client-id: ${{ inputs.client-id }}
    client-secret: ${{ inputs.client-secret }}
    tunnel-host: ${{ inputs.tunnel-host }}
    tunnel-port: ${{ inputs.tunnel-port }}
```

#### VS Code in Browser

```yaml
- uses: asd-engineering/asd-devinci@v1
  with:
    api-key: ${{ secrets.ASD_API_KEY }}
    interface: codeserver
    tunnel-name: vscode-${{ github.run_id }}
```

### GitLab CI/CD

DevInCi is available as a [GitLab CI/CD Component](https://docs.gitlab.com/ee/ci/components/). Add it to your `.gitlab-ci.yml`:

#### Basic Usage

```yaml
include:
  - component: gitlab.com/asd-engineering/asd-devinci/dev-environment@1
    inputs:
      tunnel-name: debug-$CI_PIPELINE_ID
```

#### With API Key

```yaml
include:
  - component: gitlab.com/asd-engineering/asd-devinci/dev-environment@1
    inputs:
      api-key: $ASD_API_KEY
      tunnel-name: debug-$CI_PIPELINE_ID
      ttl-minutes: '15'
```

#### VS Code in Browser

```yaml
include:
  - component: gitlab.com/asd-engineering/asd-devinci/dev-environment@1
    inputs:
      api-key: $ASD_API_KEY
      interface: codeserver
      tunnel-name: vscode-$CI_PIPELINE_ID
```

#### Custom Stage

By default the component uses the `deploy` stage. Override with:

```yaml
include:
  - component: gitlab.com/asd-engineering/asd-devinci/dev-environment@1
    inputs:
      stage: build
      tunnel-name: debug-$CI_PIPELINE_ID
```

> **Note:** On GitLab, mark your `ASD_API_KEY` and other secrets as **masked** and **protected** in **Settings > CI/CD > Variables**. GitLab does not support runtime secret masking — the `ci_mask` function is a no-op on GitLab.

## Inputs

| Input | Description | Default | Platforms |
|-------|-------------|---------|-----------|
| `api-key` | ASD API key with `cicd:provision` scope | - | Both |
| `interface` | Interface type: `ttyd` (terminal) or `codeserver` (VS Code) | `ttyd` | Both |
| `shell` | Shell: `bash`, `zsh`, `powershell` | `bash` | Both |
| `username` | Basic auth username | `asd` | Both |
| `password` | Basic auth password (auto-generated if empty) | - | Both |
| `tunnel-name` | Subdomain prefix | Short SHA | Both |
| `tunnel-host` | Tunnel server hostname (auto-detected from API) | - | Both |
| `tunnel-port` | Tunnel server SSH port (auto-detected from API) | - | Both |
| `client-id` | Pre-existing ASD client ID (skips provisioning) | - | Both |
| `client-secret` | Pre-existing ASD client secret | - | Both |
| `direct` | Use `--direct` flag for asd expose | `false` | Both |
| `ttl-minutes` | Token TTL in minutes (0 = no expiry, API key mode only) | `0` | Both |
| `asd-version` | ASD CLI release tag | `latest` | Both |
| `api-endpoint` | ASD API endpoint | `https://api.asd.host` | Both |
| `stage` | Pipeline stage for the DevInCi job | `deploy` | GitLab only |
| `component-path` | GitLab project path (override for forks) | `asd-engineering/asd-devinci` | GitLab only |

## Outputs

### GitHub Actions

Outputs are available via `${{ steps.<id>.outputs.<name> }}`:

| Output | Description |
|--------|-------------|
| `url` | Session URL with embedded credentials |
| `url-base` | Session URL without credentials |
| `tunnel-user` | Tunnel client ID |
| `local-port` | Local service port |
| `expires-at` | Token expiration (ISO 8601) |

### GitLab CI/CD

Outputs are written to a `devinci.env` [dotenv artifact](https://docs.gitlab.com/ee/ci/variables/#pass-an-environment-variable-to-another-job) for downstream jobs. The `TUNNEL_URL` variable is also used for the GitLab environment URL.

## Authentication Modes

### 1. Pre-existing Credentials (Fastest)

When `client-id` and `client-secret` are provided, provisioning is skipped entirely. Requires `tunnel-host` and `tunnel-port` to be set explicitly. Used by `asd terminal` CLI which passes credentials from its local registry.

### 2. API Key Mode (Recommended)

Use an API key with `cicd:provision` scope. The API returns all server details (host, port, ownership) automatically.

1. Create an API key at [asd.host/workspace/api-keys](https://asd.host/workspace/api-keys)
2. Enable the `cicd:provision` scope
3. Add as a secret:
   - **GitHub**: Repository secrets as `ASD_API_KEY`
   - **GitLab**: CI/CD variables as `ASD_API_KEY` (mark as masked + protected)

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

### GitHub Actions

#### Debug a Failing Job

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

#### Interactive Development with VS Code

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

### GitLab CI/CD

#### Debug a Failing Pipeline

```yaml
stages:
  - test
  - debug

test:
  stage: test
  script:
    - npm test

include:
  - component: gitlab.com/asd-engineering/asd-devinci/dev-environment@1
    inputs:
      api-key: $ASD_API_KEY
      tunnel-name: debug-$CI_PIPELINE_ID
      stage: debug

dev-environment:
  rules:
    - when: on_failure
```

#### On-demand Development Environment

```yaml
include:
  - component: gitlab.com/asd-engineering/asd-devinci/dev-environment@1
    inputs:
      api-key: $ASD_API_KEY
      interface: codeserver
      tunnel-name: dev-$CI_PIPELINE_ID

dev-environment:
  rules:
    - if: $CI_PIPELINE_SOURCE == "web"
      when: manual
```

## Security

- Credentials are embedded in the URL for one-click access
- URLs use HTTPS with TLS encryption
- Tokens have configurable TTL (ephemeral mode uses short-lived tokens)
- Basic auth protects the endpoint
- **GitHub Actions**: Secrets are masked in logs via `::add-mask::`
- **GitLab CI/CD**: No runtime secret masking — mark CI/CD variables as "masked" in project settings

## Requirements

- **GitHub Actions**: ubuntu, macos, or windows runner
- **GitLab CI/CD**: Any runner with Docker executor (uses `ubuntu:22.04` image)
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

### GitLab: Secrets visible in logs

GitLab does not support runtime secret masking. Mark your CI/CD variables as **masked** in **Settings > CI/CD > Variables**. Variables marked as masked are redacted from job logs by the runner.

### GitLab: "git clone" fails in before_script

The component clones the script repository using `CI_JOB_TOKEN`. If the component project is private, ensure the consumer project has access via **Settings > CI/CD > Token Access**.

## Release

### GitHub Actions

Use `@v1` for the latest stable version:

```yaml
- uses: asd-engineering/asd-devinci@v1
```

### GitLab CI/CD

Use `@1` for the latest compatible version:

```yaml
include:
  - component: gitlab.com/asd-engineering/asd-devinci/dev-environment@1
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- [ASD](https://asd.host)
- [Documentation](https://asd.host/docs)
- [API Key Management](https://asd.host/workspace/api-keys)
