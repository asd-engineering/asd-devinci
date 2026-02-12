# CLAUDE.md

## Overview

**asd-devinci** is a reusable GitHub Composite Action that spins up a full development environment inside a GitHub Actions runner and exposes it via ASD tunnels. Any project with an `asd.yaml` can use it.

## Structure

```
asd-devinci/
├── action.yml              # Composite action definition
├── scripts/
│   ├── install-asd.sh      # Download + install ASD CLI binary
│   ├── setup-tunnel.sh     # Generate ephemeral tunnel credentials
│   └── keep-alive.sh       # Health check loop
├── README.md
├── CLAUDE.md
├── LICENSE
└── .gitignore
```

## How It Works

1. Sets up Node.js + pnpm
2. Installs project dependencies
3. Downloads ASD CLI from GitHub releases
4. Creates ephemeral tunnel credentials via ASD API
5. Sets auth environment variables (ttyd, code-server)
6. Runs `asd run dev` (or custom command) - this bootstraps the full stack from the project's `asd.yaml`
7. Keeps the session alive until the workflow is cancelled or times out

## Consumer Usage

Projects add a thin workflow:

```yaml
- uses: asd-engineering/asd-devinci@main
  with:
    asd-api-key: ${{ secrets.ASD_API_KEY }}
    username: ${{ inputs.username }}
    password: ${{ inputs.password }}
```

## Key Inputs

- `asd-command`: Override the automation command (default: `asd run dev`)
- `asd-version`: Pin ASD CLI version (default: `latest`)
- `tunnel-name`: Custom tunnel name (default: short SHA)
- `node-version`: Node.js version (default: `22`)
