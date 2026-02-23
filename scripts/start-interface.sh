#!/bin/bash
set -euo pipefail

INTERFACE="${INTERFACE_TYPE:-ttyd}"
echo "::group::Starting ASD DevInCi (${INTERFACE})"

# Generate password if not provided
if [ -z "${SESSION_PASSWORD:-}" ]; then
  SESSION_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
  echo "::add-mask::${SESSION_PASSWORD}"
fi

# Set defaults
SESSION_USERNAME="${SESSION_USERNAME:-asd}"
SESSION_SHELL="${SESSION_SHELL:-bash}"

# Export for subsequent steps (using generic names)
echo "SESSION_PASSWORD=${SESSION_PASSWORD}" >> "$GITHUB_ENV"
echo "SESSION_USERNAME=${SESSION_USERNAME}" >> "$GITHUB_ENV"
echo "SESSION_SHELL=${SESSION_SHELL}" >> "$GITHUB_ENV"

# Export ASD ttyd env vars for ASD CLI
echo "ASD_TTYD_PASSWORD=${SESSION_PASSWORD}" >> "$GITHUB_ENV"
echo "ASD_TTYD_USERNAME=${SESSION_USERNAME}" >> "$GITHUB_ENV"
echo "ASD_TTYD_SHELL_CMD=${SESSION_SHELL}" >> "$GITHUB_ENV"

# Initialize ASD workspace (creates workspace directory, .env file)
export ASD_NON_INTERACTIVE=1
export CI=true

# Ensure ASD_BIN_DIR is set (from setup.sh step)
# This tells ASD CLI where to find helper binaries like ttyd, caddy, etc.
if [ -z "${ASD_BIN_DIR:-}" ]; then
  # Fallback: determine based on OS
  if [ "$(uname)" = "Darwin" ]; then
    ASD_BIN_DIR="${HOME}/Library/Application Support/asd/bin"
  else
    ASD_BIN_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/asd/bin"
  fi
fi
export ASD_BIN_DIR

# Ensure PATH includes the bin directory
export PATH="${ASD_BIN_DIR}:${PATH}"

echo "ASD_BIN_DIR: ${ASD_BIN_DIR}"
echo "Binaries available:"
ls -la "$ASD_BIN_DIR" 2>/dev/null || echo "  (directory not found)"

# IMPORTANT: Export credentials BEFORE asd init, because asd.yaml may have
# auto_start_ttyd/auto_start_codeserver which would start services during init.
# Without these exports, auto-started services get auto-generated credentials
# instead of the user-provided ones.
export ASD_TTYD_USERNAME="${SESSION_USERNAME}"
export ASD_TTYD_PASSWORD="${SESSION_PASSWORD}"
export ASD_TTYD_SHELL_CMD="${SESSION_SHELL}"
if [ "${INTERFACE}" = "codeserver" ]; then
  export ASD_CODESERVER_AUTH=password
  export ASD_CODESERVER_PASSWORD="${SESSION_PASSWORD}"
fi

# Create workspace if asd init isn't available
WORKSPACE_DIR="${GITHUB_WORKSPACE}/workspace"
mkdir -p "$WORKSPACE_DIR"

# Pre-seed .env with credentials so asd init's merge policy preserves them
cat > ".env" << EOF
ASD_TTYD_USERNAME=${SESSION_USERNAME}
ASD_TTYD_PASSWORD=${SESSION_PASSWORD}
ASD_TTYD_SHELL_CMD=${SESSION_SHELL}
EOF
if [ "${INTERFACE}" = "codeserver" ]; then
  cat >> ".env" << EOF
ASD_CODESERVER_AUTH=password
ASD_CODESERVER_PASSWORD=${SESSION_PASSWORD}
EOF
fi
chmod 600 .env

# Try asd init first
if asd init --yes 2>/dev/null; then
  echo "Workspace initialized via asd init"
  # Restrict .env permissions before writing secrets
  if [ -f ".env" ]; then
    chmod 600 .env
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
  fi
else
  echo "Setting up workspace manually"
  echo "ASD_WORKSPACE_DIR=${WORKSPACE_DIR}" >> "$GITHUB_ENV"
  export ASD_WORKSPACE_DIR="${WORKSPACE_DIR}"
fi

# Ensure workspace dir is set after init
export ASD_WORKSPACE_DIR="${ASD_WORKSPACE_DIR:-${WORKSPACE_DIR}}"

# Write to .env for ASD commands
cat >> ".env" << EOF
ASD_TTYD_USERNAME=${ASD_TTYD_USERNAME}
ASD_TTYD_PASSWORD=${ASD_TTYD_PASSWORD}
ASD_TTYD_SHELL_CMD=${ASD_TTYD_SHELL_CMD}
ASD_WORKSPACE_DIR=${ASD_WORKSPACE_DIR}
EOF
chmod 600 .env

if [ "${INTERFACE}" = "codeserver" ]; then
  # Start code-server
  echo "Starting code-server (VS Code in browser)..."

  echo "ASD_CODESERVER_AUTH=password" >> "$GITHUB_ENV"
  echo "ASD_CODESERVER_PASSWORD=${SESSION_PASSWORD}" >> "$GITHUB_ENV"

  if asd code start 2>&1; then
    # Source updated .env for port
    set -a
    # shellcheck disable=SC1091
    source .env || true
    set +a
    PORT="${ASD_CODESERVER_PORT:-8080}"
    echo "code-server started on port ${PORT}"
  else
    echo "::error::Failed to start code-server"
    exit 1
  fi
else
  # Start ttyd (default)
  echo "Starting ttyd (web terminal)..."

  if asd ttyd start 2>&1; then
    echo "ttyd started successfully"
  else
    echo "::error::Failed to start ttyd"
    exit 1
  fi

  # Source updated .env for port
  if [ -f ".env" ]; then
    set -a
    # shellcheck disable=SC1091
    source .env || true
    set +a
  fi
  PORT="${ASD_TTYD_PORT:-7681}"
  echo "ttyd started on port ${PORT}"
fi

# Export port to GITHUB_ENV
echo "SESSION_PORT=${PORT}" >> "$GITHUB_ENV"
echo "ASD_TTYD_PORT=${PORT}" >> "$GITHUB_ENV"

# Set output
echo "port=${PORT}" >> "$GITHUB_OUTPUT"

# Verify the interface is accessible
echo "Verifying interface is accessible..."
for i in {1..10}; do
  HTTP_CODE=$(curl -so /dev/null -w '%{http_code}' "http://localhost:${PORT}/" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" -gt 0 ] 2>/dev/null && [ "$HTTP_CODE" -lt 500 ] 2>/dev/null; then
    echo "Interface accessible on port ${PORT}"
    break
  fi
  if [ "$i" -eq 10 ]; then
    echo "::warning::Interface may not be fully ready yet"
  fi
  sleep 1
done

echo ""
echo "ASD DevInCi ready:"
echo "  Interface: ${INTERFACE}"
echo "  Port: ${PORT}"
echo "  Username: ${SESSION_USERNAME}"
echo ""

echo "::endgroup::"
