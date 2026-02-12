#!/usr/bin/env bash
set -euo pipefail

ASD_ENDPOINT="https://dokizgwigyyqeodjwyhz.supabase.co"
TUNNEL_HOST="${TUNNEL_HOST:-cicd.eu1.asd.engineer}"
TUNNEL_PORT="${TUNNEL_PORT:-2223}"
NAME="${TUNNEL_NAME:-${GITHUB_SHA:0:7}}"

echo "Setting up tunnel credentials..."
echo "  Name: $NAME"
echo "  Host: $TUNNEL_HOST"

# Create ephemeral credentials via edge function
RESPONSE=$(curl -sf "${ASD_ENDPOINT}/functions/v1/create-ephemeral-token" \
  -H "Content-Type: application/json" \
  -d "{\"source\": \"github-actions\", \"repo\": \"${GITHUB_REPOSITORY:-unknown}\"}")

if [ -z "$RESPONSE" ]; then
  echo "Failed to create ephemeral credentials"
  exit 1
fi

ASD_CLIENT_ID=$(echo "$RESPONSE" | jq -r '.tunnel_client_id')
ASD_CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.tunnel_client_secret')

if [ -z "$ASD_CLIENT_ID" ] || [ "$ASD_CLIENT_ID" = "null" ]; then
  echo "Invalid response from API"
  echo "$RESPONSE"
  exit 1
fi

# Export credentials to environment
echo "ASD_CLIENT_ID=$ASD_CLIENT_ID" >> "$GITHUB_ENV"
echo "ASD_CLIENT_SECRET=$ASD_CLIENT_SECRET" >> "$GITHUB_ENV"
echo "ASD_TUNNEL_HOST=$TUNNEL_HOST" >> "$GITHUB_ENV"
echo "ASD_TUNNEL_PORT=$TUNNEL_PORT" >> "$GITHUB_ENV"

# Set output for tunnel URL
TUNNEL_URL="https://${NAME}-${ASD_CLIENT_ID}.${TUNNEL_HOST}/"
echo "url=$TUNNEL_URL" >> "$GITHUB_OUTPUT"

# Upload tunnel URL as artifact for CLI retrieval
mkdir -p workspace
echo "$TUNNEL_URL" > workspace/tunnel-url.txt

echo ""
echo "=============================================="
echo "Tunnel credentials ready"
echo "URL: $TUNNEL_URL"
echo "=============================================="
