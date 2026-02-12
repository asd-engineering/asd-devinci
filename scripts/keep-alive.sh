#!/usr/bin/env bash

echo "DeVinci Cloud IDE session is active"
echo "  The session will remain active for up to 6 hours"
echo "  Cancel the workflow run to terminate early"
echo ""

COUNTER=0
while true; do
  sleep 60
  COUNTER=$((COUNTER + 1))
  HOURS=$((COUNTER / 60))
  MINS=$((COUNTER % 60))

  STATUS="active"

  # Optional health checks (non-blocking)
  if curl -sf http://127.0.0.1:4200 > /dev/null 2>&1; then
    STATUS="$STATUS | app: up"
  fi

  if curl -sf http://127.0.0.1:54321/rest/v1/ > /dev/null 2>&1; then
    STATUS="$STATUS | supabase: up"
  fi

  echo "$(date '+%H:%M:%S') [${HOURS}h${MINS}m] $STATUS"
done
