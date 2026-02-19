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
_APPEND_USER_TO_SUBDOMAIN="${APPEND_USER_TO_SUBDOMAIN:-true}"
_DIRECT_MODE="${DIRECT_MODE:-false}"

# Initialize workspace + generate .env from tpl.env macros
asd init --yes

# Source .env for port if available
if [ -f ".env" ]; then
  # shellcheck disable=SC1091
  source .env || true
fi

# Get the port (prefer SESSION_PORT, fallback to ASD_TTYD_PORT)
PORT="${SESSION_PORT:-${ASD_TTYD_PORT:-7681}}"

# Get credentials (prefer SESSION_*, fallback to ASD_TTYD_*)
USERNAME="${SESSION_USERNAME:-${ASD_TTYD_USERNAME:-asd}}"
PASSWORD="${SESSION_PASSWORD:-${ASD_TTYD_PASSWORD:-}}"

# Restore tunnel credentials (use saved values, not .env values)
ASD_CLIENT_ID="${_ASD_CLIENT_ID}"
ASD_CLIENT_SECRET="${_ASD_CLIENT_SECRET}"
ASD_TUNNEL_HOST="${_ASD_TUNNEL_HOST}"
ASD_TUNNEL_PORT="${_ASD_TUNNEL_PORT}"
APPEND_USER_TO_SUBDOMAIN="${_APPEND_USER_TO_SUBDOMAIN}"
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

# URL construction based on append_user_to_subdomain flag from server registry
if [ "$APPEND_USER_TO_SUBDOMAIN" = "true" ] && [ -n "$ASD_CLIENT_ID" ]; then
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

---
*Powered by [DevInCi](https://asd.host) - Dev in CI by ASD*
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

# Write to .env for the asd command
cat >> ".env" << EOF
ASD_CLIENT_ID=${ASD_CLIENT_ID}
ASD_CLIENT_SECRET=${ASD_CLIENT_SECRET}
ASD_TUNNEL_HOST=${ASD_TUNNEL_HOST}
ASD_TUNNEL_PORT=${ASD_TUNNEL_PORT}
EOF

# Source the updated .env
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

echo "Connecting tunnel: ${NAME} on port ${PORT} (service: ${SERVICE_ID})"

# Expose the service via tunnel
env \
  ASD_CLIENT_ID="${ASD_CLIENT_ID}" \
  ASD_CLIENT_SECRET="${ASD_CLIENT_SECRET}" \
  ASD_TUNNEL_HOST="${ASD_TUNNEL_HOST}" \
  ASD_TUNNEL_PORT="${ASD_TUNNEL_PORT}" \
  asd expose "${EXPOSE_ARGS[@]}"

echo "::endgroup::"

echo ""
echo "Session active. Cancel the workflow run to terminate."
echo ""

# Keep the workflow alive until cancelled (asd expose returns immediately)
while true; do
  sleep 60
  echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC'): session active"
done
