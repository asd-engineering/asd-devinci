#!/bin/bash
set -euo pipefail

ASD_ENDPOINT="${ASD_ENDPOINT:-https://api.asd.host}"

echo "=== Integration Tests Against Production ==="
echo ""

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Helper function to report test result
report_result() {
  local test_name="$1"
  local result="$2"
  local message="${3:-}"

  if [ "$result" = "PASS" ]; then
    echo "PASS: $test_name"
    ((TESTS_PASSED++))
  elif [ "$result" = "SKIP" ]; then
    echo "SKIP: $test_name - $message"
    ((TESTS_SKIPPED++))
  else
    echo "FAIL: $test_name - $message"
    ((TESTS_FAILED++))
  fi
}

# Test 1: API key provisioning
test_api_key_provision() {
  echo ""
  echo "Test 1: API key provisioning..."

  if [ -z "${ASD_TEST_API_KEY:-}" ]; then
    report_result "API key provisioning" "SKIP" "ASD_TEST_API_KEY not set"
    return 0
  fi

  RESPONSE=$(curl -sf "${ASD_ENDPOINT}/functions/v1/credential-provision" \
    -H "X-API-Key: ${ASD_TEST_API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"project": "github-action-test", "environment": "ci", "ttl_minutes": 5}' 2>&1) || {
    report_result "API key provisioning" "FAIL" "curl failed: $RESPONSE"
    return 1
  }

  TOKEN=$(echo "$RESPONSE" | jq -r '.token // empty' 2>/dev/null || echo "")
  TUNNEL_USER=$(echo "$RESPONSE" | jq -r '.tunnel_user // empty' 2>/dev/null || echo "")
  CLIENT_ID=$(echo "$RESPONSE" | jq -r '.client_id // empty' 2>/dev/null || echo "")
  EXPIRES_AT=$(echo "$RESPONSE" | jq -r '.expires_at // empty' 2>/dev/null || echo "")

  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    local ERROR=$(echo "$RESPONSE" | jq -r '.error // .message // "Unknown error"' 2>/dev/null || echo "Unknown error")
    report_result "API key provisioning" "FAIL" "No token in response: $ERROR"
    return 1
  fi

  # Validate tunnel_user format (5 alphanumeric chars)
  if ! echo "$TUNNEL_USER" | grep -qE '^[a-z0-9]{5}$'; then
    report_result "API key provisioning" "FAIL" "Invalid tunnel_user format: $TUNNEL_USER"
    return 1
  fi

  # Save for subsequent tests
  export PROVISIONED_TOKEN="$TOKEN"
  export PROVISIONED_TUNNEL_USER="$TUNNEL_USER"

  report_result "API key provisioning" "PASS"
  echo "   - tunnel_user: $TUNNEL_USER"
  echo "   - client_id: $CLIENT_ID"
  echo "   - expires_at: $EXPIRES_AT"
}

# Test 2: Verify the provisioned token
test_token_verification() {
  echo ""
  echo "Test 2: Token verification..."

  if [ -z "${PROVISIONED_TOKEN:-}" ] || [ -z "${PROVISIONED_TUNNEL_USER:-}" ]; then
    report_result "Token verification" "SKIP" "No provisioned token from Test 1"
    return 0
  fi

  RESPONSE=$(curl -sf "${ASD_ENDPOINT}/functions/v1/verify-tunnel-token" \
    -H "Content-Type: application/json" \
    -d "{\"user\": \"${PROVISIONED_TUNNEL_USER}\", \"password\": \"${PROVISIONED_TOKEN}\"}" 2>&1) || {
    report_result "Token verification" "FAIL" "curl failed: $RESPONSE"
    return 1
  }

  VALID=$(echo "$RESPONSE" | jq -r '.valid // "false"' 2>/dev/null || echo "false")

  if [ "$VALID" != "true" ]; then
    report_result "Token verification" "FAIL" "Token not valid: $RESPONSE"
    return 1
  fi

  report_result "Token verification" "PASS"
}

# Test 3: Invalid API key rejection
test_invalid_api_key() {
  echo ""
  echo "Test 3: Invalid API key rejection..."

  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    "${ASD_ENDPOINT}/functions/v1/credential-provision" \
    -H "X-API-Key: invalid-key-12345-not-real" \
    -H "Content-Type: application/json" \
    -d '{"project": "test"}' \
    --max-time 10 2>/dev/null) || {
    report_result "Invalid API key rejection" "FAIL" "curl failed"
    return 1
  }

  if [ "$HTTP_CODE" != "401" ]; then
    report_result "Invalid API key rejection" "FAIL" "Expected 401, got $HTTP_CODE"
    return 1
  fi

  report_result "Invalid API key rejection" "PASS"
}

# Test 4: Ephemeral token creation
test_ephemeral_token() {
  echo ""
  echo "Test 4: Ephemeral token creation..."

  RESPONSE=$(curl -sf "${ASD_ENDPOINT}/functions/v1/create-ephemeral-token" \
    -H "Content-Type: application/json" \
    -d '{"source": "integration-test:cloud-terminal-action"}' 2>&1) || {
    report_result "Ephemeral token creation" "FAIL" "curl failed: $RESPONSE"
    return 1
  }

  CLIENT_ID=$(echo "$RESPONSE" | jq -r '.tunnel_client_id // empty' 2>/dev/null || echo "")
  CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.tunnel_client_secret // empty' 2>/dev/null || echo "")
  TUNNEL_HOST=$(echo "$RESPONSE" | jq -r '.tunnel_host // empty' 2>/dev/null || echo "")
  EXPIRES_AT=$(echo "$RESPONSE" | jq -r '.expires_at // empty' 2>/dev/null || echo "")

  if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
    local ERROR=$(echo "$RESPONSE" | jq -r '.error // "Unknown error"' 2>/dev/null || echo "Unknown error")
    report_result "Ephemeral token creation" "FAIL" "No client_id in response: $ERROR"
    return 1
  fi

  if [ -z "$CLIENT_SECRET" ] || [ "$CLIENT_SECRET" = "null" ]; then
    report_result "Ephemeral token creation" "FAIL" "No client_secret in response"
    return 1
  fi

  if [ -z "$TUNNEL_HOST" ] || [ "$TUNNEL_HOST" = "null" ]; then
    report_result "Ephemeral token creation" "FAIL" "No tunnel_host in response"
    return 1
  fi

  report_result "Ephemeral token creation" "PASS"
  echo "   - tunnel_client_id: $CLIENT_ID"
  echo "   - tunnel_host: $TUNNEL_HOST"
  echo "   - expires_at: $EXPIRES_AT"
}

# Test 5: API key without required scope rejection
test_missing_scope() {
  echo ""
  echo "Test 5: API key scope validation..."

  if [ -z "${ASD_TEST_API_KEY_NO_SCOPE:-}" ]; then
    report_result "API key scope validation" "SKIP" "ASD_TEST_API_KEY_NO_SCOPE not set"
    return 0
  fi

  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    "${ASD_ENDPOINT}/functions/v1/credential-provision" \
    -H "X-API-Key: ${ASD_TEST_API_KEY_NO_SCOPE}" \
    -H "Content-Type: application/json" \
    -d '{"project": "test"}' \
    --max-time 10 2>/dev/null) || {
    report_result "API key scope validation" "FAIL" "curl failed"
    return 1
  }

  if [ "$HTTP_CODE" != "403" ]; then
    report_result "API key scope validation" "FAIL" "Expected 403, got $HTTP_CODE"
    return 1
  fi

  report_result "API key scope validation" "PASS"
}

# Test 6: Rate limiting for ephemeral tokens
test_rate_limiting() {
  echo ""
  echo "Test 6: Rate limiting behavior..."

  # This test just verifies we get a proper response (not testing actual rate limit)
  # Full rate limit testing would require making many requests

  RESPONSE=$(curl -sf "${ASD_ENDPOINT}/functions/v1/create-ephemeral-token" \
    -H "Content-Type: application/json" \
    -d '{"source": "rate-limit-test"}' 2>&1) || {
    # If rate limited, we get a 429
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
      "${ASD_ENDPOINT}/functions/v1/create-ephemeral-token" \
      -H "Content-Type: application/json" \
      -d '{"source": "rate-limit-test"}' 2>/dev/null)

    if [ "$HTTP_CODE" = "429" ]; then
      report_result "Rate limiting behavior" "PASS" "(hit rate limit as expected)"
      return 0
    fi

    report_result "Rate limiting behavior" "FAIL" "Unexpected failure: $RESPONSE"
    return 1
  }

  report_result "Rate limiting behavior" "PASS" "(endpoint responded normally)"
}

# Run tests
echo "Starting integration tests against production API..."
echo "Endpoint: ${ASD_ENDPOINT}"
echo ""

test_api_key_provision || true
test_token_verification || true
test_invalid_api_key || true
test_ephemeral_token || true
test_missing_scope || true
test_rate_limiting || true

# Summary
echo ""
echo "=============================================="
echo "TEST SUMMARY"
echo "=============================================="
echo "  Passed:  ${TESTS_PASSED}"
echo "  Failed:  ${TESTS_FAILED}"
echo "  Skipped: ${TESTS_SKIPPED}"
echo "=============================================="
echo ""

if [ "${TESTS_FAILED}" -gt 0 ]; then
  echo "=== SOME TESTS FAILED ==="
  exit 1
else
  echo "=== ALL TESTS PASSED ==="
  exit 0
fi
