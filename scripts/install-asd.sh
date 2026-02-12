#!/usr/bin/env bash
set -euo pipefail

# Resolve ASD version
if [ -z "${ASD_VERSION:-}" ] || [ "$ASD_VERSION" = "latest" ]; then
  TAG=$(gh release view --repo asd-engineering/asd-cli --json tagName -q '.tagName')
  echo "Resolved 'latest' to $TAG"
else
  TAG="$ASD_VERSION"
fi

echo "Installing ASD CLI $TAG..."

# Download and extract
gh release download "$TAG" \
  --repo asd-engineering/asd-cli \
  --pattern "asd-linux-x64.tar.gz" \
  --dir /tmp

sudo tar -xzf /tmp/asd-linux-x64.tar.gz -C /usr/local --strip-components=1

# Move main asd binary to bin/ (it extracts to /usr/local/asd, not /usr/local/bin/asd)
sudo mv /usr/local/asd /usr/local/bin/asd || true
sudo chmod +x /usr/local/bin/asd /usr/local/bin/ttyd /usr/local/bin/caddy /usr/local/bin/asd-tunnel || true

echo "/usr/local/bin" >> "$GITHUB_PATH"

# Verify installation
echo "ASD CLI installed:"
asd version || echo "Warning: asd version check failed"
