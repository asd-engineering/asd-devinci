# CLAUDE.md

## Overview

**asd-devinci** (DevInCi = Dev in CI) is a reusable GitHub Composite Action that spins up a full development environment inside a GitHub Actions runner with web terminal (ttyd), VS Code (code-server), and ASD tunnel access. Just click the URL to connect.

## Structure

```
asd-devinci/
├── action.yml                         # Composite action definition
├── scripts/
│   ├── setup.sh                       # Download + install ASD CLI (cross-platform)
│   ├── provision.sh                   # Provision tunnel credentials (API key or ephemeral)
│   ├── start-interface.sh             # Start ttyd or code-server
│   └── connect.sh                     # Connect tunnel + generate URLs
├── tests/
│   └── integration/
│       └── prod-api.test.sh           # API integration tests
├── README.md
├── CLAUDE.md
├── LICENSE
└── .gitignore
```

## How It Works

1. Installs ASD CLI from GitHub releases (cross-platform: Linux, macOS, Windows)
2. Provisions tunnel credentials:
   - **API key mode** (recommended): calls `credential-provision` with `X-API-Key` header
   - **Ephemeral mode** (fallback): calls `create-ephemeral-token` (no auth, 5 min limit)
3. Starts interface (ttyd web terminal or code-server VS Code)
4. Connects tunnel via `asd expose` with provisioned credentials
5. Outputs clickable URL with embedded basic auth credentials

## Key Design Decisions

- **No hardcoded defaults** for tunnel-host/tunnel-port: always read from API response or explicit input
- **X-API-Key header** for API key auth (not Authorization: Bearer)
- **API endpoint** defaults to `https://api.asd.host` (not raw Supabase URL)
- **Tunnel host/port** auto-detected from API response — provision step sets `GITHUB_ENV`

## Consumer Usage

```yaml
- uses: asd-engineering/asd-devinci@v1
  with:
    api-key: ${{ secrets.ASD_API_KEY }}
    tunnel-name: debug-${{ github.run_id }}
    ttl-minutes: 15
```

## Key Inputs

- `api-key`: ASD API key with `cicd:provision` scope (recommended)
- `interface`: `ttyd` (terminal) or `codeserver` (VS Code)
- `tunnel-name`: Custom subdomain prefix (default: short SHA)
- `ttl-minutes`: Token TTL in minutes (5-60, API key mode only)
- `keep-alive`: Keep session alive after setup (`true`/`false`)
- `asd-version`: ASD CLI release tag (default: `latest`)
