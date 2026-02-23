#!/bin/bash
set -euo pipefail

ASD_ENDPOINT="${ASD_ENDPOINT:-https://api.asd.host}"

# Mask API key early to prevent leaking in logs
if [ -n "${ASD_API_KEY:-}" ]; then
  echo "::add-mask::${ASD_API_KEY}"
fi
if [ -n "${INPUT_CLIENT_SECRET:-}" ]; then
  echo "::add-mask::${INPUT_CLIENT_SECRET}"
fi

# Normalize special region values to empty (let API decide)
if [ "${REGION:-}" = "User Default" ] || [ "${REGION:-}" = "default" ]; then
  REGION=""
fi

# Validate region for safe JSON interpolation
if [ -n "${REGION:-}" ] && [[ ! "$REGION" =~ ^[a-z0-9-]*$ ]]; then
  echo "::error::Invalid region '${REGION}'. Must be lowercase alphanumeric with hyphens."
  exit 1
fi

echo "::group::Provisioning tunnel credentials"

if [ -n "${INPUT_CLIENT_ID:-}" ] && [ -n "${INPUT_CLIENT_SECRET:-}" ]; then
  # === PRE-EXISTING CREDENTIALS MODE ===
  # Used when CLI passes credentials from local registry (e.g. asd gh terminal)
  echo "Using provided client credentials (skipping provisioning)"
  ASD_CLIENT_ID="$INPUT_CLIENT_ID"
  ASD_CLIENT_SECRET="$INPUT_CLIENT_SECRET"
  echo "::add-mask::${ASD_CLIENT_SECRET}"
  EXPIRES_AT="N/A (pre-existing)"
  OWNERSHIP_TYPE="shared"

  # tunnel-host and tunnel-port MUST be provided with pre-existing credentials
  if [ -z "${ASD_TUNNEL_HOST:-}" ]; then
    echo "::error::tunnel-host required when using pre-existing credentials"
    exit 1
  fi
  if [ -z "${ASD_TUNNEL_PORT:-}" ]; then
    echo "::error::tunnel-port required when using pre-existing credentials"
    exit 1
  fi

  echo "Using pre-existing credentials: client_id=${ASD_CLIENT_ID}"

elif [ -n "${ASD_API_KEY:-}" ]; then
  # === API KEY MODE ===
  # Provisions credentials via credential-provision endpoint with configurable TTL
  echo "Using API key authentication (credential-provision)"

  RESPONSE=$(curl -sf "${ASD_ENDPOINT}/functions/v1/credential-provision" \
    -H "X-API-Key: ${ASD_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"project\": \"${GITHUB_REPOSITORY}\",
      \"ttl_minutes\": ${TTL_MINUTES:-0},
      $([ -n "${REGION:-}" ] && printf '\"region\": \"%s\",' "$REGION")
      \"metadata\": {
        \"github_run_id\": \"${GITHUB_RUN_ID}\",
        \"github_repository\": \"${GITHUB_REPOSITORY}\"
      }
    }" 2>&1) || {
    echo "::error::Failed to provision credentials via API key"
    echo "Response: $RESPONSE"
    exit 1
  }

  if [ -z "$RESPONSE" ]; then
    echo "::error::Empty response from credential-provision endpoint"
    exit 1
  fi

  # Validate response is JSON
  if ! echo "$RESPONSE" | jq -e . >/dev/null 2>&1; then
    echo "::error::API returned invalid JSON. Response: ${RESPONSE:0:200}"
    exit 1
  fi

  # Check for error in response
  ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // empty' 2>/dev/null || echo "")
  if [ -n "$ERROR_MSG" ]; then
    MSG=$(echo "$RESPONSE" | jq -r '.message // "Unknown error"' 2>/dev/null || echo "Unknown error")
    echo "::error::API error: ${ERROR_MSG} - ${MSG}"
    exit 1
  fi

  # Parse response
  ASD_CLIENT_ID=$(echo "$RESPONSE" | jq -r '.tunnel_client_id')
  ASD_CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.tunnel_client_secret')
  echo "::add-mask::${ASD_CLIENT_SECRET}"
  EXPIRES_AT=$(echo "$RESPONSE" | jq -r '.expires_at')
  OWNERSHIP_TYPE=$(echo "$RESPONSE" | jq -r '.ownership_type // "shared"')
  APPEND_USER=$(echo "$RESPONSE" | jq -r '.append_user_to_subdomain // empty')

  if [ "$ASD_CLIENT_ID" = "null" ] || [ -z "$ASD_CLIENT_ID" ]; then
    echo "::error::Invalid API response: missing tunnel_client_id"
    echo "Response: $RESPONSE"
    exit 1
  fi

  # Use FQDN for URL construction, fall back to host
  FQDN_FROM_API=$(echo "$RESPONSE" | jq -r '.tunnel_fqdn // empty')
  HOST_FROM_API=$(echo "$RESPONSE" | jq -r '.tunnel_host // empty')
  PORT_FROM_API=$(echo "$RESPONSE" | jq -r '.tunnel_port // empty')

  # Priority: explicit input > API fqdn > API host
  ASD_TUNNEL_HOST="${ASD_TUNNEL_HOST:-${FQDN_FROM_API:-$HOST_FROM_API}}"
  ASD_TUNNEL_PORT="${ASD_TUNNEL_PORT:-$PORT_FROM_API}"

  echo "Provisioned via API key: tunnel_user=${ASD_CLIENT_ID}, expires=${EXPIRES_AT}"

else
  # === EPHEMERAL MODE ===
  # Public endpoint, no auth needed — short-lived tokens
  echo "Creating ephemeral tunnel credentials..."
  echo "::warning::Ephemeral tokens are short-lived. Use an API key for longer sessions."

  RESPONSE=$(curl -sf "${ASD_ENDPOINT}/functions/v1/create-ephemeral-token" \
    -H "Content-Type: application/json" \
    -d "{
      \"source\": \"github-action:devinci\",
      \"repo\": \"${GITHUB_REPOSITORY:-unknown}\"
    }" 2>&1) || {
    echo "::error::Failed to create ephemeral token"
    echo "Response: $RESPONSE"
    exit 1
  }

  if [ -z "$RESPONSE" ]; then
    echo "::error::Empty response from create-ephemeral-token endpoint"
    exit 1
  fi

  # Validate response is JSON
  if ! echo "$RESPONSE" | jq -e . >/dev/null 2>&1; then
    echo "::error::API returned invalid JSON. Response: ${RESPONSE:0:200}"
    exit 1
  fi

  # Check for error in response
  ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // empty' 2>/dev/null || echo "")
  if [ -n "$ERROR_MSG" ]; then
    MSG=$(echo "$RESPONSE" | jq -r '.message // "Unknown error"' 2>/dev/null || echo "Unknown error")
    echo "::error::API error: ${ERROR_MSG} - ${MSG}"
    exit 1
  fi

  # Parse response
  ASD_CLIENT_ID=$(echo "$RESPONSE" | jq -r '.tunnel_client_id')
  ASD_CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.tunnel_client_secret')
  echo "::add-mask::${ASD_CLIENT_SECRET}"
  EXPIRES_AT=$(echo "$RESPONSE" | jq -r '.expires_at')
  OWNERSHIP_TYPE=$(echo "$RESPONSE" | jq -r '.ownership_type // "shared"')
  APPEND_USER=$(echo "$RESPONSE" | jq -r '.append_user_to_subdomain // empty')

  if [ "$ASD_CLIENT_ID" = "null" ] || [ -z "$ASD_CLIENT_ID" ]; then
    echo "::error::Invalid response: missing tunnel_client_id"
    echo "Response: $RESPONSE"
    exit 1
  fi

  # Use FQDN for URL construction, fall back to host
  FQDN_FROM_API=$(echo "$RESPONSE" | jq -r '.tunnel_fqdn // empty')
  HOST_FROM_API=$(echo "$RESPONSE" | jq -r '.tunnel_host // empty')
  PORT_FROM_API=$(echo "$RESPONSE" | jq -r '.tunnel_port // empty')

  # Priority: explicit input > API fqdn > API host
  ASD_TUNNEL_HOST="${ASD_TUNNEL_HOST:-${FQDN_FROM_API:-$HOST_FROM_API}}"
  ASD_TUNNEL_PORT="${ASD_TUNNEL_PORT:-$PORT_FROM_API}"

  echo "Provisioned ephemeral: tunnel_user=${ASD_CLIENT_ID}, expires=${EXPIRES_AT}"
fi

# Validate we have tunnel server details (no defaults — must come from API or input)
if [ -z "${ASD_TUNNEL_HOST:-}" ]; then
  echo "::error::No tunnel host available. API response must include tunnel_fqdn or tunnel_host, or provide tunnel-host input."
  exit 1
fi
if [ -z "${ASD_TUNNEL_PORT:-}" ]; then
  echo "::error::No tunnel port available. API response must include tunnel_port, or provide tunnel-port input."
  exit 1
fi

# Export credentials to environment for subsequent steps
echo "ASD_CLIENT_ID=${ASD_CLIENT_ID}" >> "$GITHUB_ENV"
echo "ASD_CLIENT_SECRET=${ASD_CLIENT_SECRET}" >> "$GITHUB_ENV"
echo "ASD_TUNNEL_HOST=${ASD_TUNNEL_HOST}" >> "$GITHUB_ENV"
echo "ASD_TUNNEL_PORT=${ASD_TUNNEL_PORT}" >> "$GITHUB_ENV"
echo "TUNNEL_OWNERSHIP=${OWNERSHIP_TYPE}" >> "$GITHUB_ENV"
echo "APPEND_USER_TO_SUBDOMAIN=${APPEND_USER:-true}" >> "$GITHUB_ENV"
echo "ASD_EXPIRES_AT=${EXPIRES_AT}" >> "$GITHUB_ENV"

# Export API key for in-session ASD CLI use (e.g. asd auth, asd net apply)
if [ -n "${ASD_API_KEY:-}" ]; then
  echo "ASD_API_KEY=${ASD_API_KEY}" >> "$GITHUB_ENV"
fi

# Set outputs for subsequent steps
echo "client_id=${ASD_CLIENT_ID}" >> "$GITHUB_OUTPUT"
echo "expires_at=${EXPIRES_AT}" >> "$GITHUB_OUTPUT"

echo "Tunnel: ${ASD_TUNNEL_HOST}:${ASD_TUNNEL_PORT}"
echo "::endgroup::"
