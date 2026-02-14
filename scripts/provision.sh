#!/bin/bash
set -euo pipefail

ASD_ENDPOINT="${ASD_ENDPOINT:-https://api.asd.host}"

echo "::group::Provisioning tunnel credentials"

if [ -n "${ASD_API_KEY:-}" ]; then
  # === API KEY MODE ===
  echo "Using API key authentication (credential-provision)"

  RESPONSE=$(curl -sf "${ASD_ENDPOINT}/functions/v1/credential-provision" \
    -H "X-API-Key: ${ASD_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"project\": \"${GITHUB_REPOSITORY}\",
      \"environment\": \"ci\",
      \"ttl_minutes\": ${TTL_MINUTES:-15},
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

  # Check for error in response
  ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // empty' 2>/dev/null || echo "")
  if [ -n "$ERROR_MSG" ]; then
    MSG=$(echo "$RESPONSE" | jq -r '.message // "Unknown error"' 2>/dev/null || echo "Unknown error")
    echo "::error::API error: ${ERROR_MSG} - ${MSG}"
    exit 1
  fi

  # Parse response
  ASD_CLIENT_ID=$(echo "$RESPONSE" | jq -r '.tunnel_user')
  ASD_CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.token')
  TUNNEL_USER_CLIENT_ID=$(echo "$RESPONSE" | jq -r '.client_id')
  EXPIRES_AT=$(echo "$RESPONSE" | jq -r '.expires_at')

  if [ "$ASD_CLIENT_ID" = "null" ] || [ -z "$ASD_CLIENT_ID" ]; then
    echo "::error::Invalid API response: missing tunnel_user"
    echo "Response: $RESPONSE"
    exit 1
  fi

  # Read tunnel host/port from API response (API knows the right server)
  TUNNEL_HOST_FROM_API=$(echo "$RESPONSE" | jq -r '.tunnel_host // empty')
  TUNNEL_PORT_FROM_API=$(echo "$RESPONSE" | jq -r '.tunnel_port // empty')

  # Priority: explicit input > API response
  if [ -n "${TUNNEL_HOST_FROM_API}" ]; then
    ASD_TUNNEL_HOST="${ASD_TUNNEL_HOST:-$TUNNEL_HOST_FROM_API}"
  fi
  if [ -n "${TUNNEL_PORT_FROM_API}" ]; then
    ASD_TUNNEL_PORT="${ASD_TUNNEL_PORT:-$TUNNEL_PORT_FROM_API}"
  fi

  echo "Provisioned via API key: tunnel_user=${ASD_CLIENT_ID}, client_id=${TUNNEL_USER_CLIENT_ID}, expires=${EXPIRES_AT}"

else
  # === EPHEMERAL MODE ===
  echo "Using ephemeral authentication (create-ephemeral-token)"
  echo "::warning::Using ephemeral token (limited). Consider using an API key for production."

  RESPONSE=$(curl -sf "${ASD_ENDPOINT}/functions/v1/create-ephemeral-token" \
    -H "Content-Type: application/json" \
    -d "{\"source\": \"github-action:cloud-terminal\", \"repo\": \"${GITHUB_REPOSITORY:-unknown}\"}" 2>&1) || {
    echo "::error::Failed to create ephemeral token"
    echo "Response: $RESPONSE"
    exit 1
  }

  if [ -z "$RESPONSE" ]; then
    echo "::error::Empty response from create-ephemeral-token endpoint"
    exit 1
  fi

  # Check for error in response
  ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // empty' 2>/dev/null || echo "")
  if [ -n "$ERROR_MSG" ]; then
    echo "::error::API error: ${ERROR_MSG}"
    exit 1
  fi

  # Parse response
  ASD_CLIENT_ID=$(echo "$RESPONSE" | jq -r '.tunnel_client_id')
  ASD_CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.tunnel_client_secret')
  TUNNEL_HOST=$(echo "$RESPONSE" | jq -r '.tunnel_host')
  TUNNEL_PORT=$(echo "$RESPONSE" | jq -r '.tunnel_port')
  EXPIRES_AT=$(echo "$RESPONSE" | jq -r '.expires_at')

  if [ "$ASD_CLIENT_ID" = "null" ] || [ -z "$ASD_CLIENT_ID" ]; then
    echo "::error::Invalid ephemeral token response: missing tunnel_client_id"
    echo "Response: $RESPONSE"
    exit 1
  fi

  # Override tunnel host/port from ephemeral response if provided
  if [ "$TUNNEL_HOST" != "null" ] && [ -n "$TUNNEL_HOST" ]; then
    echo "ASD_TUNNEL_HOST=${TUNNEL_HOST}" >> "$GITHUB_ENV"
  fi
  if [ "$TUNNEL_PORT" != "null" ] && [ -n "$TUNNEL_PORT" ]; then
    echo "ASD_TUNNEL_PORT=${TUNNEL_PORT}" >> "$GITHUB_ENV"
  fi

  echo "Provisioned ephemeral: tunnel_user=${ASD_CLIENT_ID}, expires=${EXPIRES_AT}"
fi

# Export credentials to environment for subsequent steps
echo "ASD_CLIENT_ID=${ASD_CLIENT_ID}" >> "$GITHUB_ENV"
echo "ASD_CLIENT_SECRET=${ASD_CLIENT_SECRET}" >> "$GITHUB_ENV"

# Set tunnel host/port if not already set by API response
# Priority: explicit input > API response > fail
if ! grep -q "ASD_TUNNEL_HOST=" "$GITHUB_ENV" 2>/dev/null; then
  if [ -n "${ASD_TUNNEL_HOST:-}" ]; then
    echo "ASD_TUNNEL_HOST=${ASD_TUNNEL_HOST}" >> "$GITHUB_ENV"
  else
    echo "::error::No tunnel host available. Provide tunnel-host input or use an API key/ephemeral mode (which returns tunnel_host in the response)."
    exit 1
  fi
fi
if ! grep -q "ASD_TUNNEL_PORT=" "$GITHUB_ENV" 2>/dev/null; then
  if [ -n "${ASD_TUNNEL_PORT:-}" ]; then
    echo "ASD_TUNNEL_PORT=${ASD_TUNNEL_PORT}" >> "$GITHUB_ENV"
  else
    echo "::error::No tunnel port available. Provide tunnel-port input or use an API key/ephemeral mode (which returns tunnel_port in the response)."
    exit 1
  fi
fi

# Set outputs for subsequent steps
echo "client_id=${ASD_CLIENT_ID}" >> "$GITHUB_OUTPUT"
echo "expires_at=${EXPIRES_AT}" >> "$GITHUB_OUTPUT"

# Also export expires_at for connect.sh
echo "ASD_EXPIRES_AT=${EXPIRES_AT}" >> "$GITHUB_ENV"

# Mask the secret from logs
echo "::add-mask::${ASD_CLIENT_SECRET}"

echo "::endgroup::"
