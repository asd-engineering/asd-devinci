#!/bin/bash
# CI Platform Abstraction Layer
# Provides CI-agnostic functions for GitHub Actions, GitLab CI, and local execution.
# Source this file at the top of each script: source "${SCRIPTS_DIR}/lib/ci.sh"

# Guard against double-sourcing
[ -n "${_CI_LIB_LOADED:-}" ] && return 0
_CI_LIB_LOADED=1

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  CI_PLATFORM="github"
elif [ -n "${GITLAB_CI:-}" ]; then
  CI_PLATFORM="gitlab"
else
  CI_PLATFORM="local"
fi
export CI_PLATFORM

# ---------------------------------------------------------------------------
# Normalized CI variables
# ---------------------------------------------------------------------------
case "$CI_PLATFORM" in
  github)
    CI_REPO="${GITHUB_REPOSITORY:-}"
    CI_RUN_ID="${GITHUB_RUN_ID:-}"
    CI_COMMIT="${GITHUB_SHA:-}"
    CI_WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
    CI_TOKEN="${GITHUB_TOKEN:-}"
    CI_RUNNER_OS="${RUNNER_OS:-Linux}"
    CI_RUNNER_ARCH="${RUNNER_ARCH:-X64}"
    ;;
  gitlab)
    CI_REPO="${CI_PROJECT_PATH:-}"
    CI_RUN_ID="${CI_PIPELINE_ID:-}"
    CI_COMMIT="${CI_COMMIT_SHA:-}"
    CI_WORKSPACE="${CI_PROJECT_DIR:-$(pwd)}"
    CI_TOKEN="${CI_JOB_TOKEN:-}"
    # Normalize uname to match GitHub Actions conventions
    case "$(uname -s)" in
      Linux*)  CI_RUNNER_OS="Linux" ;;
      Darwin*) CI_RUNNER_OS="macOS" ;;
      MINGW*|MSYS*|CYGWIN*) CI_RUNNER_OS="Windows" ;;
      *)       CI_RUNNER_OS="Linux" ;;
    esac
    case "$(uname -m)" in
      x86_64|amd64) CI_RUNNER_ARCH="X64" ;;
      aarch64|arm64) CI_RUNNER_ARCH="ARM64" ;;
      *)             CI_RUNNER_ARCH="X64" ;;
    esac
    ;;
  local)
    CI_REPO="${GITHUB_REPOSITORY:-${CI_PROJECT_PATH:-unknown/local}}"
    CI_RUN_ID="${GITHUB_RUN_ID:-${CI_PIPELINE_ID:-local}}"
    CI_COMMIT="${GITHUB_SHA:-${CI_COMMIT_SHA:-$(git rev-parse HEAD 2>/dev/null || echo 'unknown')}}"
    CI_WORKSPACE="${GITHUB_WORKSPACE:-${CI_PROJECT_DIR:-$(pwd)}}"
    CI_TOKEN=""
    case "$(uname -s)" in
      Linux*)  CI_RUNNER_OS="Linux" ;;
      Darwin*) CI_RUNNER_OS="macOS" ;;
      MINGW*|MSYS*|CYGWIN*) CI_RUNNER_OS="Windows" ;;
      *)       CI_RUNNER_OS="Linux" ;;
    esac
    case "$(uname -m)" in
      x86_64|amd64) CI_RUNNER_ARCH="X64" ;;
      aarch64|arm64) CI_RUNNER_ARCH="ARM64" ;;
      *)             CI_RUNNER_ARCH="X64" ;;
    esac
    ;;
esac

export CI_REPO CI_RUN_ID CI_COMMIT CI_WORKSPACE CI_TOKEN CI_RUNNER_OS CI_RUNNER_ARCH

# GitLab dotenv artifact path for cross-job outputs
if [ "$CI_PLATFORM" = "gitlab" ]; then
  CI_DEVINCI_DOTENV="${CI_DEVINCI_DOTENV:-devinci.env}"
  export CI_DEVINCI_DOTENV
fi

# ---------------------------------------------------------------------------
# GitLab section ID tracking (collapsible log sections need unique IDs)
# ---------------------------------------------------------------------------
_CI_SECTION_STACK=()

# ---------------------------------------------------------------------------
# Logging / grouping functions
# ---------------------------------------------------------------------------

ci_group_start() {
  local title="$1"
  case "$CI_PLATFORM" in
    github)
      echo "::group::${title}"
      ;;
    gitlab)
      local id
      id="devinci_$(echo "$title" | tr '[:upper:] ' '[:lower:]_' | tr -cd 'a-z0-9_')"
      _CI_SECTION_STACK+=("$id")
      printf '\e[0Ksection_start:%s:%s[collapsed=false]\r\e[0K%s\n' "$(date +%s)" "$id" "$title"
      ;;
    local)
      echo "==> ${title}"
      ;;
  esac
}

ci_group_end() {
  case "$CI_PLATFORM" in
    github)
      echo "::endgroup::"
      ;;
    gitlab)
      if [ ${#_CI_SECTION_STACK[@]} -gt 0 ]; then
        local id="${_CI_SECTION_STACK[-1]}"
        unset '_CI_SECTION_STACK[-1]'
        printf '\e[0Ksection_end:%s:%s\r\e[0K\n' "$(date +%s)" "$id"
      fi
      ;;
    local)
      echo ""
      ;;
  esac
}

ci_error() {
  local msg="$1"
  case "$CI_PLATFORM" in
    github)  echo "::error::${msg}" ;;
    gitlab)  printf '\e[31mERROR: %s\e[0m\n' "$msg" >&2 ;;
    local)   printf 'ERROR: %s\n' "$msg" >&2 ;;
  esac
}

ci_warning() {
  local msg="$1"
  case "$CI_PLATFORM" in
    github)  echo "::warning::${msg}" ;;
    gitlab)  printf '\e[33mWARNING: %s\e[0m\n' "$msg" >&2 ;;
    local)   printf 'WARNING: %s\n' "$msg" >&2 ;;
  esac
}

# ---------------------------------------------------------------------------
# Secret masking
# ---------------------------------------------------------------------------

ci_mask() {
  local val="$1"
  [ -z "$val" ] && return 0
  case "$CI_PLATFORM" in
    github)  echo "::add-mask::${val}" ;;
    gitlab)  : ;; # GitLab masks via CI/CD variable settings, no runtime API
    local)   : ;;
  esac
}

# ---------------------------------------------------------------------------
# Environment & output helpers
# ---------------------------------------------------------------------------

ci_set_env() {
  local key="$1" val="$2"
  case "$CI_PLATFORM" in
    github)
      echo "${key}=${val}" >> "$GITHUB_ENV"
      ;;
    gitlab)
      export "${key}=${val}"
      ;;
    local)
      export "${key}=${val}"
      ;;
  esac
}

ci_set_output() {
  local key="$1" val="$2"
  case "$CI_PLATFORM" in
    github)
      echo "${key}=${val}" >> "$GITHUB_OUTPUT"
      ;;
    gitlab)
      # Write to dotenv artifact for downstream jobs, and export for current shell
      echo "${key}=${val}" >> "$CI_DEVINCI_DOTENV"
      export "${key}=${val}"
      ;;
    local)
      echo "OUTPUT: ${key}=${val}"
      export "${key}=${val}"
      ;;
  esac
}

ci_add_path() {
  local dir="$1"
  case "$CI_PLATFORM" in
    github)
      echo "${dir}" >> "$GITHUB_PATH"
      ;;
    gitlab|local)
      export PATH="${dir}:${PATH}"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Step summary
# ---------------------------------------------------------------------------

ci_set_summary() {
  local markdown="$1"
  case "$CI_PLATFORM" in
    github)
      echo "$markdown" >> "$GITHUB_STEP_SUMMARY"
      ;;
    gitlab)
      echo "$markdown"
      # Also write to artifact file for visibility
      mkdir -p workspace
      echo "$markdown" > workspace/summary.md
      ;;
    local)
      echo "$markdown"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Deployment helpers (GitHub Deployments API / GitLab environment keyword)
# ---------------------------------------------------------------------------

# Creates a GitHub deployment; no-op on GitLab (uses environment: keyword in YAML).
# Sets DEPLOY_ID variable on success.
ci_create_deployment() {
  local environment="$1"
  local description="$2"
  local url="$3"
  DEPLOY_ID=""

  case "$CI_PLATFORM" in
    github)
      if [ -z "${CI_TOKEN:-}" ] || [ -z "${CI_REPO:-}" ]; then
        return 0
      fi
      echo "Creating GitHub deployment..."
      DEPLOY_ID=$(curl -sf -X POST \
        -H "Authorization: token ${CI_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${CI_REPO}/deployments" \
        -d "{
          \"ref\": \"${CI_COMMIT:-HEAD}\",
          \"environment\": \"${environment}\",
          \"description\": \"${description}\",
          \"auto_merge\": false,
          \"required_contexts\": []
        }" | jq -r '.id' 2>/dev/null) || true

      if [ -n "$DEPLOY_ID" ] && [ "$DEPLOY_ID" != "null" ]; then
        curl -sf -X POST \
          -H "Authorization: token ${CI_TOKEN}" \
          -H "Accept: application/vnd.github+json" \
          "https://api.github.com/repos/${CI_REPO}/deployments/${DEPLOY_ID}/statuses" \
          -d "{
            \"state\": \"success\",
            \"environment_url\": \"${url}\",
            \"description\": \"ASD DevInCi session ready\"
          }" > /dev/null 2>&1 || true
        ci_set_env "DEPLOY_ID" "$DEPLOY_ID"
        echo "Deployment created: View deployment button now visible"
      else
        ci_warning "Could not create deployment (check permissions)"
        DEPLOY_ID=""
      fi
      ;;
    gitlab|local)
      # GitLab uses environment: keyword in component YAML; no API call needed
      :
      ;;
  esac
}

# Marks a GitHub deployment as inactive; no-op on GitLab.
ci_deactivate_deployment() {
  local deploy_id="${1:-${DEPLOY_ID:-}}"
  case "$CI_PLATFORM" in
    github)
      if [ -n "$deploy_id" ] && [ "$deploy_id" != "null" ] && [ -n "${CI_TOKEN:-}" ]; then
        curl -sf -X POST \
          -H "Authorization: token ${CI_TOKEN}" \
          -H "Accept: application/vnd.github+json" \
          "https://api.github.com/repos/${CI_REPO}/deployments/${deploy_id}/statuses" \
          -d '{"state": "inactive"}' > /dev/null 2>&1 || true
        echo "Deployment marked inactive"
      fi
      ;;
    gitlab|local)
      :
      ;;
  esac
}
