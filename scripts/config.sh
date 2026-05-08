#!/bin/bash

# =============================================================================
# Shared Configuration for Local Scripts
# =============================================================================
# This file reads configuration from group_vars/all/vars.yml to avoid
# hardcoded values scattered across multiple scripts.
#
# Source this file in other scripts:
#   source "$(dirname "$0")/config.sh"
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m'

# =============================================================================
# Helper Functions to Read from vars.yml
# =============================================================================

# Read a simple value from vars.yml
get_var() {
  local key=$1
  grep "^${key}:" "$PROJECT_DIR/group_vars/all/vars.yml" 2>/dev/null | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'"
}

# Read a list from vars.yml (returns space-separated values)
get_var_list() {
  local key=$1
  awk "/^${key}:$/,/^[a-z_]+:/" "$PROJECT_DIR/group_vars/all/vars.yml" | grep "^\s*-\s*\"" | sed 's/.*"\(.*\)".*/\1/' | tr '\n' ' '
}

# Read domain records from vars.yml
get_domains_config() {
  "$PROJECT_DIR/scripts/app-catalog.py" domains-shell
}

# =============================================================================
# Configuration Values (loaded from vars.yml)
# =============================================================================

# GitHub Configuration
GITHUB_OWNER=$(get_var "github_username")

load_local_github_token() {
  [ -f "$PROJECT_DIR/.env" ] || return 0
  [ -z "${GH_TOKEN:-}" ] || return 0

  local token
  token=$(grep -E '^(GH_TOKEN|GITHUB_TOKEN|GITHUB_PAT_TOKEN)=' "$PROJECT_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
  if [ -n "$token" ]; then
    export GH_TOKEN="$token"
    export GH_TOKEN_SOURCE=".env"
  fi
}

load_local_github_token

# Primary Domain
PRIMARY_DOMAIN=$(get_var "primary_domain")

# =============================================================================
# Dynamic Functions (read from inventory/vault)
# =============================================================================

# Get VPS IP from inventory
get_vps_ip() {
  grep -v "^#" "$PROJECT_DIR/inventory/hosts.ini" | grep -v "^\[" | grep -v "^$" | head -1 | awk '{print $1}'
}

# Get a connection field from the first inventory host line.
get_inventory_field() {
  local field=$1
  awk -v target="$field" '
    NF && $1 !~ /^\[/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ ("^" target "=")) {
          split($i, a, "=")
          print a[2]
          exit
        }
      }
    }
  ' "$PROJECT_DIR/inventory/hosts.ini" 2>/dev/null || true
}

# SSH Configuration
SSH_KEY_NAME=$(get_var "ssh_key_name")
SSH_KEY_PATH="${HOME}/.ssh/${SSH_KEY_NAME}"
DEPLOY_USER=$(get_var "deploy_user")
CI_DEPLOY_USER=$(get_var "ci_deploy_user")
SSH_PORT=$(get_inventory_field "ansible_port")
if [ -z "$SSH_PORT" ]; then
  SSH_PORT=$(get_var "ssh_port")
fi

# Get GitHub token from vault
get_github_token() {
  ansible-vault view "$PROJECT_DIR/group_vars/all/vault.yml" --vault-password-file="$PROJECT_DIR/.vault_pass" 2>/dev/null | \
    grep "vault_github_token:" | awk '{print $2}' | tr -d '"'
}

# Get Cloudflare API token from vault
get_cf_token() {
  ansible-vault view "$PROJECT_DIR/group_vars/all/vault.yml" --vault-password-file="$PROJECT_DIR/.vault_pass" 2>/dev/null | \
    grep "vault_cloudflare_api_token:" | awk '{print $2}' | tr -d '"'
}

# Get Cloudflare account email from vault. Required when using Global API Key.
get_cf_email() {
  ansible-vault view "$PROJECT_DIR/group_vars/all/vault.yml" --vault-password-file="$PROJECT_DIR/.vault_pass" 2>/dev/null | \
    grep "vault_cloudflare_email:" | awk '{print $2}' | tr -d '"'
}

detect_cloudflare_auth() {
  local credential=$1
  local token_check

  token_check=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
    -H "Authorization: Bearer $credential" | jq -r '.success // false' 2>/dev/null)
  if [ "$token_check" = "true" ]; then
    echo "api_token"
    return 0
  fi

  CF_EMAIL="${CF_EMAIL:-$(get_cf_email)}"
  if [ -n "$CF_EMAIL" ]; then
    local key_check
    key_check=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $credential" | jq -r '.success // false' 2>/dev/null)
    if [ "$key_check" = "true" ]; then
      echo "global_key"
      return 0
    fi
  fi

  return 1
}

cloudflare_request() {
  local method=$1
  local url=$2
  shift 2

  if [ "${CF_AUTH_TYPE:-api_token}" = "global_key" ]; then
    curl -s -X "$method" "$url" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_CREDENTIAL" \
      "$@"
  else
    curl -s -X "$method" "$url" \
      -H "Authorization: Bearer $CF_CREDENTIAL" \
      "$@"
  fi
}

# =============================================================================
# Repository List (loaded from vars.yml)
# =============================================================================

# Load repositories into array
load_repositories() {
  ALL_REPOS=()
  while IFS= read -r repo; do
    [ -n "$repo" ] && ALL_REPOS+=("$repo")
  done < <("$PROJECT_DIR/scripts/app-catalog.py" repo-refs)
}

# =============================================================================
# Domains Configuration (loaded from vars.yml)
# =============================================================================

# Load domains into associative array
declare -A DOMAINS_CONFIG

load_domains() {
  while IFS=: read -r domain records; do
    [ -n "$domain" ] && DOMAINS_CONFIG["$domain"]="$records"
  done < <(get_domains_config)
}

# =============================================================================
# Validation Functions
# =============================================================================

check_requirements() {
  local missing=()
  
  if ! command -v gh &> /dev/null; then
    missing+=("gh (GitHub CLI)")
  fi
  
  if ! command -v jq &> /dev/null; then
    missing+=("jq")
  fi
  
  if ! command -v curl &> /dev/null; then
    missing+=("curl")
  fi
  
  if ! command -v ansible-vault &> /dev/null; then
    missing+=("ansible-vault")
  fi
  
  if [ ${#missing[@]} -gt 0 ]; then
    echo -e "${RED}✗ Missing required tools:${NC}"
    for tool in "${missing[@]}"; do
      echo "  - $tool"
    done
    return 1
  fi
  
  return 0
}

check_files() {
  local missing=()
  
  if [ ! -f "$PROJECT_DIR/.vault_pass" ]; then
    missing+=(".vault_pass")
  fi
  
  if [ ! -f "$SSH_KEY_PATH" ]; then
    missing+=("$SSH_KEY_PATH")
  fi
  
  if [ ${#missing[@]} -gt 0 ]; then
    echo -e "${RED}✗ Missing required files:${NC}"
    for file in "${missing[@]}"; do
      echo "  - $file"
    done
    return 1
  fi
  
  return 0
}

check_gh_auth() {
  load_local_github_token
  if [ -n "${GH_TOKEN:-}" ]; then
    if gh api user &> /dev/null; then
      return 0
    fi
    if [ "${GH_TOKEN_SOURCE:-}" = ".env" ]; then
      unset GH_TOKEN
      unset GH_TOKEN_SOURCE
    else
      echo -e "${RED}✗ GH_TOKEN is not accepted by gh api${NC}"
      return 1
    fi
  fi

  if gh auth status &> /dev/null; then
    return 0
  fi

  local vault_token
  vault_token=$(get_github_token)
  if [ -n "$vault_token" ]; then
    export GH_TOKEN="$vault_token"
    export GH_TOKEN_SOURCE="vault"
    if gh api user &> /dev/null; then
      return 0
    fi
  fi

  echo -e "${RED}✗ GitHub CLI not authenticated. Run: gh auth login or update vault_github_token/.env${NC}"
  return 1
}

# =============================================================================
# Initialize (load all config)
# =============================================================================

init_config() {
  load_repositories
  load_domains
}

# Auto-initialize when sourced
init_config
