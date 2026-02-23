#!/bin/bash
set -euo pipefail

echo "::group::Installing ASD CLI ${ASD_VERSION:-latest}"

# Determine asset name based on OS/arch
case "${RUNNER_OS}-${RUNNER_ARCH}" in
  Linux-X64)   ASSET="asd-linux-x64.tar.gz" ;;
  Linux-ARM64) ASSET="asd-linux-arm64.tar.gz" ;;
  macOS-X64)   ASSET="asd-darwin-x64.tar.gz" ;;
  macOS-ARM64) ASSET="asd-darwin-arm64.tar.gz" ;;
  Windows-X64) ASSET="asd-windows-x64.zip" ;;
  *) echo "::error::Unsupported platform: ${RUNNER_OS}-${RUNNER_ARCH}"; exit 1 ;;
esac

# Download from GitHub releases
# NOTE: CLI releases are published to asd-cli (public repo)
VERSION="${ASD_VERSION:-latest}"
if [ "$VERSION" = "latest" ]; then
  DOWNLOAD_URL="https://github.com/asd-engineering/asd-cli/releases/latest/download/${ASSET}"
else
  # Ensure version has 'v' prefix to match GitHub release tags
  case "$VERSION" in
    v*) TAG="$VERSION" ;;
    *)  TAG="v${VERSION}" ;;
  esac
  DOWNLOAD_URL="https://github.com/asd-engineering/asd-cli/releases/download/${TAG}/${ASSET}"
fi

echo "Downloading: ${DOWNLOAD_URL}"

# Create temp directory
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

if [ "$RUNNER_OS" = "Windows" ]; then
  # Windows: binaries go to %LOCALAPPDATA%/asd/bin
  curl -fsSL "${DOWNLOAD_URL}" -o "$TMPDIR/asd-cli.zip"

  ASD_BIN_DIR="${LOCALAPPDATA}/asd/bin"
  mkdir -p "$ASD_BIN_DIR"

  # Extract (zip may have top-level dir like asd-windows-x64/)
  unzip -q "$TMPDIR/asd-cli.zip" -d "$TMPDIR/extract"
  # Handle both flat (bin/*) and nested (asd-windows-x64/bin/*) archive layouts
  if [ -d "$TMPDIR/extract/bin" ]; then
    cp "$TMPDIR/extract/bin/"* "$ASD_BIN_DIR/"
  else
    cp "$TMPDIR/extract/"*/bin/* "$ASD_BIN_DIR/"
  fi

  echo "${ASD_BIN_DIR}" >> "$GITHUB_PATH"
  echo "ASD_BIN_DIR=${ASD_BIN_DIR}" >> "$GITHUB_ENV"
  echo "Installed to ${ASD_BIN_DIR}"
else
  # Linux/macOS: binaries go to ~/.local/share/asd/bin (where ASD CLI expects them)
  curl -fsSL "${DOWNLOAD_URL}" -o "$TMPDIR/asd-cli.tar.gz"

  # Determine ASD bin directory based on OS
  if [ "$RUNNER_OS" = "macOS" ]; then
    ASD_BIN_DIR="${HOME}/Library/Application Support/asd/bin"
  else
    ASD_BIN_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/asd/bin"
  fi
  mkdir -p "$ASD_BIN_DIR"

  # Extract (--strip-components=1 removes top-level dir like asd-linux-x64/)
  mkdir -p "$TMPDIR/extract"
  tar -xzf "$TMPDIR/asd-cli.tar.gz" -C "$TMPDIR/extract" --strip-components=1

  # Install to ASD bin directory (where ASD CLI looks for helper binaries)
  cp "$TMPDIR/extract/bin/"* "$ASD_BIN_DIR/"
  chmod +x "$ASD_BIN_DIR"/*

  # Add to PATH for direct execution
  echo "${ASD_BIN_DIR}" >> "$GITHUB_PATH"
  # Export for subsequent steps so ASD CLI knows where binaries are
  echo "ASD_BIN_DIR=${ASD_BIN_DIR}" >> "$GITHUB_ENV"

  echo "Installed to ${ASD_BIN_DIR}"
fi

# macOS: ttyd from releases might need Homebrew version in some cases
# (the released binary should work, but keep this as fallback)
if [ "$RUNNER_OS" = "macOS" ] && ! "${ASD_BIN_DIR}/ttyd" --version &>/dev/null; then
  echo "Installing ttyd via Homebrew as fallback..."
  brew install ttyd
  cp "$(which ttyd)" "$ASD_BIN_DIR/ttyd"
fi

# Verify installation
echo ""
echo "Verifying installation..."
echo "ASD_BIN_DIR: ${ASD_BIN_DIR}"
ls -la "$ASD_BIN_DIR"
"${ASD_BIN_DIR}/asd" --version 2>/dev/null || echo "asd: installed (no --version flag)"
"${ASD_BIN_DIR}/asd-tunnel" --version 2>/dev/null || echo "asd-tunnel: installed"
"${ASD_BIN_DIR}/ttyd" --version 2>/dev/null || echo "ttyd: installed"
"${ASD_BIN_DIR}/caddy" version 2>/dev/null || echo "caddy: installed"

echo ""
echo "ASD CLI installed successfully to ${ASD_BIN_DIR}"

echo "::endgroup::"
