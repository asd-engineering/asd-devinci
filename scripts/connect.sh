#!/bin/bash
set -euo pipefail

echo "::group::Connecting tunnel"

# Get tunnel name (default to short SHA)
NAME="${TUNNEL_NAME:-${GITHUB_SHA:0:7}}"

# T5: Validate tunnel name for DNS compatibility
if [[ ! "$NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "::error::Invalid tunnel name '${NAME}'. Must be lowercase alphanumeric with hyphens, not starting/ending with hyphen."
  exit 1
fi

# S2: Mask GITHUB_TOKEN before use in curl calls
if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "::add-mask::${GITHUB_TOKEN}"
fi

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

# S3: Restrict .env file permissions after asd init
if [ -f ".env" ]; then
  chmod 600 .env
fi

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

# Write tunnel URL file for artifact upload (CLI watcher reads this)
mkdir -p workspace
echo "${TUNNEL_URL}" > workspace/tunnel-url.txt

# Expire time from provision step
EXPIRES_AT="${ASD_EXPIRES_AT:-unknown}"

# Detect interface type
INTERFACE="${INTERFACE_TYPE:-ttyd}"

# S4: Write summary without credentials in the link (GitHub does NOT mask step summary content)
cat >> "$GITHUB_STEP_SUMMARY" << EOF
## ASD DevInCi Ready

### Click to Open
**[${TUNNEL_URL}](${TUNNEL_URL})**

| Setting | Value |
|---------|-------|
| Interface | \`${INTERFACE}\` |
| Username | \`${USERNAME}\` |
| Tunnel User | \`${ASD_CLIENT_ID}\` |
| Expires | \`${EXPIRES_AT}\` |
| Local Port | \`${PORT}\` |

> Credentials are available in the workflow logs.

---
*Powered by [ASD DevInCi](https://asd.host) - Dev in CI by ASD*
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

# T1: Cleanup handler for workflow cancellation
DEPLOY_ID=""
cleanup() {
  echo ""
  echo "ASD DevInCi cleanup..."

  # Mark deployment as inactive
  if [ -n "$DEPLOY_ID" ] && [ "$DEPLOY_ID" != "null" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -sf -X POST \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/deployments/${DEPLOY_ID}/statuses" \
      -d '{"state": "inactive"}' > /dev/null 2>&1 || true
    echo "Deployment marked inactive"
  fi

  # Stop any tunnel processes started by asd expose
  asd expose stop --all 2>/dev/null || true

  # Remove .env with secrets
  rm -f .env 2>/dev/null || true

  echo "Cleanup complete"
}
trap cleanup EXIT INT TERM

# Create GitHub deployment with tunnel URL for immediate visibility
if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
  echo "Creating GitHub deployment..."
  DEPLOY_ID=$(curl -sf -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/deployments" \
    -d "{
      \"ref\": \"${GITHUB_SHA:-HEAD}\",
      \"environment\": \"devinci\",
      \"description\": \"ASD DevInCi ${INTERFACE} session\",
      \"auto_merge\": false,
      \"required_contexts\": []
    }" | jq -r '.id' 2>/dev/null) || true

  if [ -n "$DEPLOY_ID" ] && [ "$DEPLOY_ID" != "null" ]; then
    curl -sf -X POST \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/deployments/${DEPLOY_ID}/statuses" \
      -d "{
        \"state\": \"success\",
        \"environment_url\": \"${TUNNEL_URL}\",
        \"description\": \"ASD DevInCi session ready\"
      }" > /dev/null 2>&1 || true
    echo "DEPLOY_ID=${DEPLOY_ID}" >> "$GITHUB_ENV"
    echo "Deployment created: View deployment button now visible"
  else
    echo "::warning::Could not create deployment (check permissions)"
  fi
fi

# Ensure required env vars are available for asd expose
export ASD_CLIENT_ID="${ASD_CLIENT_ID}"
export ASD_CLIENT_SECRET="${ASD_CLIENT_SECRET}"
export ASD_TUNNEL_HOST="${ASD_TUNNEL_HOST}"
export ASD_TUNNEL_PORT="${ASD_TUNNEL_PORT}"
export ASD_BASIC_AUTH_USERNAME="${USERNAME}"
export ASD_BASIC_AUTH_PASSWORD="${PASSWORD}"

# Write to .env for the asd command (tunnel creds + basic auth for Caddy)
cat >> ".env" << EOF
ASD_CLIENT_ID=${ASD_CLIENT_ID}
ASD_CLIENT_SECRET=${ASD_CLIENT_SECRET}
ASD_TUNNEL_HOST=${ASD_TUNNEL_HOST}
ASD_TUNNEL_PORT=${ASD_TUNNEL_PORT}
ASD_BASIC_AUTH_USERNAME=${USERNAME}
ASD_BASIC_AUTH_PASSWORD=${PASSWORD}
EOF

# S3: Restrict .env file permissions after writing secrets
chmod 600 .env

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

# Expose the service via tunnel (asd expose sets up tunnel and returns)
if ! env \
  ASD_CLIENT_ID="${ASD_CLIENT_ID}" \
  ASD_CLIENT_SECRET="${ASD_CLIENT_SECRET}" \
  ASD_TUNNEL_HOST="${ASD_TUNNEL_HOST}" \
  ASD_TUNNEL_PORT="${ASD_TUNNEL_PORT}" \
  ASD_BASIC_AUTH_USERNAME="${ASD_BASIC_AUTH_USERNAME}" \
  ASD_BASIC_AUTH_PASSWORD="${ASD_BASIC_AUTH_PASSWORD}" \
  asd expose "${EXPOSE_ARGS[@]}"; then
  echo "::error::Tunnel connection failed"
  echo "  Host: ${ASD_TUNNEL_HOST}:${ASD_TUNNEL_PORT}"
  echo "  Client ID: ${ASD_CLIENT_ID}"
  echo "  Check: API key validity, firewall rules, tunnel server status"
  exit 1
fi

echo "::endgroup::"

echo ""
echo "Session active. Cancel the workflow run to terminate."
echo ""

# Keep alive with health checks
HEALTH_FAILURES=0
while true; do
  sleep 60

  # Health-check local service (accept any non-5xx: 401=auth-protected, 302=login redirect)
  HTTP_CODE=$(curl -so /dev/null -w '%{http_code}' "http://localhost:${PORT}/" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" -gt 0 ] 2>/dev/null && [ "$HTTP_CODE" -lt 500 ] 2>/dev/null; then
    HEALTH_FAILURES=0
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC'): session active"
  else
    ((HEALTH_FAILURES++))
    echo "::warning::Health check failed (${HEALTH_FAILURES}/3)"
    if [ "$HEALTH_FAILURES" -ge 3 ]; then
      echo "::error::Local service on port ${PORT} is unresponsive after 3 consecutive checks"
      exit 1
    fi
  fi
done
