#!/bin/bash
set -euo pipefail

echo "::group::Connecting tunnel"

# Get tunnel name (default to short SHA)
NAME="${TUNNEL_NAME:-${GITHUB_SHA:0:7}}"

# IMPORTANT: Save tunnel credentials from GITHUB_ENV BEFORE sourcing .env
# (asd init creates .env with empty ASD_TUNNEL_HOST which would overwrite our value)
_ASD_CLIENT_ID="${ASD_CLIENT_ID:-}"
_ASD_CLIENT_SECRET="${ASD_CLIENT_SECRET:-}"
_ASD_TUNNEL_HOST="${ASD_TUNNEL_HOST:-}"
_ASD_TUNNEL_PORT="${ASD_TUNNEL_PORT:-}"
_TUNNEL_OWNERSHIP="${TUNNEL_OWNERSHIP:-shared}"
_DIRECT_MODE="${DIRECT_MODE:-false}"

# Initialize workspace + generate .env from tpl.env macros
# (creates Caddy ports via getRandomPort(), ASD_PROJECT_HOST, etc.)
asd init --yes

# Source .env for port if available (but don't export all, use specific vars)
if [ -f ".env" ]; then
  # shellcheck disable=SC1091
  source .env || true
fi

# Get the port (prefer SESSION_PORT, fallback to TTYD_PORT)
PORT="${SESSION_PORT:-${TTYD_PORT:-7681}}"

# Get credentials (prefer SESSION_*, fallback to TTYD_*)
USERNAME="${SESSION_USERNAME:-${TTYD_USERNAME:-asd}}"
PASSWORD="${SESSION_PASSWORD:-${TTYD_PASSWORD:-}}"

# Restore tunnel credentials (use saved values, not .env values)
ASD_CLIENT_ID="${_ASD_CLIENT_ID}"
ASD_CLIENT_SECRET="${_ASD_CLIENT_SECRET}"
ASD_TUNNEL_HOST="${_ASD_TUNNEL_HOST}"
ASD_TUNNEL_PORT="${_ASD_TUNNEL_PORT}"
TUNNEL_OWNERSHIP="${_TUNNEL_OWNERSHIP}"
DIRECT_MODE="${_DIRECT_MODE}"

# Validate required tunnel credentials
if [ -z "$ASD_TUNNEL_HOST" ]; then
  echo "::error::ASD_TUNNEL_HOST is empty. Provision step must set it from API response or provide tunnel-host input."
  exit 1
fi
if [ -z "$ASD_TUNNEL_PORT" ]; then
  echo "::error::ASD_TUNNEL_PORT is empty. Provision step must set it from API response or provide tunnel-port input."
  exit 1
fi

# Ownership-aware URL construction (ownership from provision.sh via GITHUB_ENV)
if [ "$TUNNEL_OWNERSHIP" = "shared" ] && [ -n "$ASD_CLIENT_ID" ]; then
  URL_HOST="${NAME}-${ASD_CLIENT_ID}.${ASD_TUNNEL_HOST}"
else
  URL_HOST="${NAME}.${ASD_TUNNEL_HOST}"
fi

TUNNEL_URL="https://${URL_HOST}/"

# URL-encode credentials for embedding in URL
ENCODED_USER=$(printf '%s' "${USERNAME}" | jq -sRr @uri)
ENCODED_PASS=$(printf '%s' "${PASSWORD}" | jq -sRr @uri)
FULL_URL="https://${ENCODED_USER}:${ENCODED_PASS}@${URL_HOST}/"

# Set outputs
echo "url=${FULL_URL}" >> "$GITHUB_OUTPUT"
echo "url_base=${TUNNEL_URL}" >> "$GITHUB_OUTPUT"

# Export for keep-alive step
echo "TUNNEL_URL=${TUNNEL_URL}" >> "$GITHUB_ENV"
echo "TUNNEL_FULL_URL=${FULL_URL}" >> "$GITHUB_ENV"

# Expire time from provision step
EXPIRES_AT="${ASD_EXPIRES_AT:-unknown}"

# Detect interface type
INTERFACE="${INTERFACE_TYPE:-ttyd}"

# Write summary
cat >> "$GITHUB_STEP_SUMMARY" << EOF
## DevInCi Ready

### Click to Open
**[${TUNNEL_URL}](${FULL_URL})**

| Setting | Value |
|---------|-------|
| Interface | \`${INTERFACE}\` |
| Username | \`${USERNAME}\` |
| Tunnel User | \`${ASD_CLIENT_ID}\` |
| Expires | \`${EXPIRES_AT}\` |
| Local Port | \`${PORT}\` |

> Credentials embedded in URL - just click to access!

**Available in this session:**
- Full ASD CLI (\`asd net\`, \`asd caddy\`, \`asd expose\`, etc.)
- Network management and tunnels
- All development tools

---
*Powered by [DevInCi](https://asd.engineering) - Dev in CI by ASD*
EOF

echo ""
echo "=============================================="
echo "DEVINCI URL: ${FULL_URL}"
echo "=============================================="
echo ""
echo "   Interface:   ${INTERFACE}"
echo "   Tunnel User: ${ASD_CLIENT_ID}"
echo "   Username:    ${USERNAME}"
echo "   Local Port:  ${PORT}"
echo "   Expires:     ${EXPIRES_AT}"
echo ""
echo "=============================================="
echo ""

# Ensure required env vars are available for asd expose
export ASD_CLIENT_ID="${ASD_CLIENT_ID}"
export ASD_CLIENT_SECRET="${ASD_CLIENT_SECRET}"
export ASD_TUNNEL_HOST="${ASD_TUNNEL_HOST}"
export ASD_TUNNEL_PORT="${ASD_TUNNEL_PORT}"

# Debug: print env vars
echo "Debug: ASD_TUNNEL_HOST=${ASD_TUNNEL_HOST}"
echo "Debug: ASD_TUNNEL_PORT=${ASD_TUNNEL_PORT}"
echo "Debug: ASD_CLIENT_ID=${ASD_CLIENT_ID}"

# Write to .env for the asd command (BEFORE running the command)
cat >> ".env" << EOF
ASD_CLIENT_ID=${ASD_CLIENT_ID}
ASD_CLIENT_SECRET=${ASD_CLIENT_SECRET}
ASD_TUNNEL_HOST=${ASD_TUNNEL_HOST}
ASD_TUNNEL_PORT=${ASD_TUNNEL_PORT}
EOF

# Source the updated .env to ensure all variables are in current shell
set -a
# shellcheck disable=SC1091
source .env
set +a

# Determine service ID based on interface type
SERVICE_ID="ttyd"
if [ "${INTERFACE}" = "codeserver" ]; then
  SERVICE_ID="codeserver"
fi

# Build expose arguments
EXPOSE_ARGS=("${PORT}" "${NAME}" "--name" "${SERVICE_ID}")
if [ "${DIRECT_MODE:-false}" = "true" ]; then
  EXPOSE_ARGS+=("--direct")
fi

echo "Connecting tunnel: ${NAME} on port ${PORT} (service: ${SERVICE_ID}, direct: ${DIRECT_MODE:-false})"

# Connect tunnel
if [ "${KEEP_ALIVE:-false}" = "true" ]; then
  # Foreground mode - keeps workflow alive
  echo "Running tunnel in foreground (keep-alive mode)..."
  env \
    ASD_CLIENT_ID="${ASD_CLIENT_ID}" \
    ASD_CLIENT_SECRET="${ASD_CLIENT_SECRET}" \
    ASD_TUNNEL_HOST="${ASD_TUNNEL_HOST}" \
    ASD_TUNNEL_PORT="${ASD_TUNNEL_PORT}" \
    asd expose "${EXPOSE_ARGS[@]}"
else
  # Background mode - connect and let workflow continue
  echo "Starting tunnel in background..."

  # Run tunnel connection in background with explicit env vars
  # (nohup can lose environment in some shells)
  nohup env \
    ASD_CLIENT_ID="${ASD_CLIENT_ID}" \
    ASD_CLIENT_SECRET="${ASD_CLIENT_SECRET}" \
    ASD_TUNNEL_HOST="${ASD_TUNNEL_HOST}" \
    ASD_TUNNEL_PORT="${ASD_TUNNEL_PORT}" \
    PATH="${PATH}" \
    asd expose "${EXPOSE_ARGS[@]}" > /tmp/tunnel.log 2>&1 &
  TUNNEL_PID=$!

  # Wait for tunnel to establish
  echo "Waiting for tunnel to establish..."
  for i in {1..30}; do
    # Check if tunnel process is still running
    if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
      echo "::error::Tunnel process exited unexpectedly"
      cat /tmp/tunnel.log || true
      exit 1
    fi

    # Try to reach the tunnel URL
    if curl -sf "${TUNNEL_URL}" -o /dev/null --max-time 5 2>/dev/null; then
      echo "Tunnel established successfully"
      break
    fi

    if [ "$i" -eq 30 ]; then
      echo "::warning::Tunnel may not be fully ready yet (timeout waiting for response)"
      echo "Tunnel log:"
      cat /tmp/tunnel.log || true
    fi

    sleep 2
  done

  echo "Tunnel running in background (PID: ${TUNNEL_PID})"
fi

echo "::endgroup::"
