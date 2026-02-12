# DeVinci Cloud IDE

A reusable GitHub Action that launches a full development environment inside a GitHub Actions runner with browser access via ASD tunnels.

## Quick Start

Add this workflow to any project with an `asd.yaml`:

```yaml
name: DeVinci Cloud IDE

on:
  workflow_dispatch:
    inputs:
      username:
        description: 'Username for ttyd/code-server'
        required: true
        type: string
      password:
        description: 'Password for ttyd/code-server'
        required: true
        type: string

jobs:
  devinci:
    runs-on: ubuntu-latest
    timeout-minutes: 360
    steps:
      - uses: actions/checkout@v4

      - uses: asd-engineering/asd-devinci@main
        with:
          asd-api-key: ${{ secrets.ASD_API_KEY }}
          username: ${{ inputs.username }}
          password: ${{ inputs.password }}
```

## What You Get

- Full application stack running in CI (bootstrapped from your `asd.yaml`)
- Browser-based terminal (ttyd) with basic auth
- Code editor (code-server) with basic auth
- Supabase local development (if configured)
- All services accessible via ASD tunnel URLs
- ASD Hub for unified access to all services
- Session stays alive for up to 6 hours

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `asd-api-key` | Yes | - | ASD API key for tunnel credentials |
| `username` | Yes | - | Basic auth username |
| `password` | Yes | - | Basic auth password |
| `asd-version` | No | `latest` | ASD CLI version to install |
| `asd-command` | No | `asd run dev` | Automation command to run |
| `tunnel-name` | No | Short SHA | Custom tunnel name |
| `tunnel-host` | No | `cicd.eu1.asd.engineer` | Tunnel server host |
| `tunnel-port` | No | `2223` | Tunnel server SSH port |
| `node-version` | No | `22` | Node.js version |

## Outputs

| Output | Description |
|--------|-------------|
| `tunnel-url` | Base tunnel URL for the environment |

## Requirements

- Repository must have an `asd.yaml` configuration file
- `ASD_API_KEY` secret configured in the repository
- The `asd.yaml` must define an automation sequence (default: `dev`)

## How It Works

1. Sets up Node.js and pnpm
2. Installs project dependencies via `pnpm install`
3. Downloads and installs ASD CLI from GitHub releases
4. Creates ephemeral tunnel credentials via ASD API
5. Sets authentication environment variables
6. Runs your automation command (`asd run dev` by default)
7. Displays access URLs via ASD Hub
8. Keeps the session alive until cancelled or timeout

## License

MIT
