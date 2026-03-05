# CLAUDE.md

## Overview

**asd-devinci** (DevInCi = Dev in CI) is a reusable GitHub Composite Action that spins up a full development environment inside GitHub Actions runners with web terminal (ttyd), VS Code (code-server), and ASD tunnel access. Just click the URL to connect.

## Structure

```
asd-devinci/
├── action.yml                         # Composite action definition
├── scripts/
│   ├── lib/
│   │   └── ci.sh                      # CI platform abstraction layer
│   ├── setup.sh                       # Download + install ASD CLI (cross-platform)
│   ├── provision.sh                   # Provision tunnel credentials (3 modes)
│   ├── start-interface.sh             # Start ttyd or code-server
│   └── connect.sh                     # Connect tunnel + generate URLs
├── .github/workflows/
│   ├── ci.yml                         # CI pipeline (shellcheck)
│   └── devinci.yml                    # Self-test workflow
├── README.md
├── CLAUDE.md
├── LICENSE
└── .gitignore
```

## How It Works

1. Installs ASD CLI from GitHub releases (cross-platform: Linux, macOS, Windows)
2. Provisions tunnel credentials (3 modes):
   - **Pre-existing credentials**: `client-id` + `client-secret` provided, skips API calls
   - **API key mode** (recommended): calls `credential-provision` with `X-API-Key` header
   - **Ephemeral mode** (fallback): calls `create-ephemeral-token` (no auth, limited)
3. Starts interface (ttyd web terminal or code-server VS Code)
4. Connects tunnel via `asd expose` with provisioned credentials
5. Outputs clickable URL with embedded basic auth credentials

## Key Design Decisions

- **CI-agnostic scripts**: Scripts use `scripts/lib/ci.sh` abstraction layer (shared with GitLab component in separate repo)
- **No hardcoded defaults** for tunnel-host/tunnel-port: always read from API response or explicit input
- **No hardcoded port defaults**: Ports come from tpl.env / asd env init, parsed from asd start output
- **X-API-Key header** for API key auth (not Authorization: Bearer)
- **API endpoint** defaults to `https://api.asd.host` (not raw Supabase URL)
- **Server discovery from API**: tunnel_host, tunnel_port, ownership_type all returned by API
- **Ownership-aware URLs**: shared = `name-clientid.host`, dedicated = `name.host`
- **--direct flag**: optional bypass of Caddy proxy via `direct` input

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
- `client-id` + `client-secret`: Pre-existing credentials (skips provisioning)
- `interface`: `ttyd` (terminal) or `codeserver` (VS Code)
- `tunnel-name`: Custom subdomain prefix (default: short SHA)
- `tunnel-host` / `tunnel-port`: Optional overrides (auto-detected from API)
- `direct`: Use `--direct` flag for asd expose
- `ttl-minutes`: Token TTL in minutes (0 = no expiry, API key mode only)
- `asd-version`: ASD CLI release tag (default: `latest`)

## Related

- **GitLab CI/CD Component**: [accelerated-software-development/devinci](https://gitlab.com/accelerated-software-development/devinci) (separate repo)
