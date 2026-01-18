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
  # Returns associative array style: domain:records
  awk '/^managed_domains:$/,/^[a-z_]+:/' "$PROJECT_DIR/group_vars/all/vars.yml" | \
    grep -E "^\s+-\s+name:|^\s+records:" | \
    paste - - | \
    sed 's/.*name:\s*"\([^"]*\)".*records:\s*"\([^"]*\)".*/\1:\2/'
}

# =============================================================================
# Configuration Values (loaded from vars.yml)
# =============================================================================

# GitHub Configuration
GITHUB_OWNER=$(get_var "github_username")

# SSH Configuration  
SSH_KEY_NAME=$(get_var "ssh_key_name")
SSH_KEY_PATH="${HOME}/.ssh/${SSH_KEY_NAME}"
DEPLOY_USER=$(get_var "deploy_user")
SSH_PORT=$(get_var "ssh_port")

# Primary Domain
PRIMARY_DOMAIN=$(get_var "primary_domain")

# =============================================================================
# Dynamic Functions (read from inventory/vault)
# =============================================================================

# Get VPS IP from inventory
get_vps_ip() {
  grep -v "^#" "$PROJECT_DIR/inventory/hosts.ini" | grep -v "^\[" | grep -v "^$" | head -1 | awk '{print $1}'
}

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

# =============================================================================
# Repository List (loaded from vars.yml)
# =============================================================================

# Load repositories into array
load_repositories() {
  ALL_REPOS=()
  local in_repos=false
  while IFS= read -r line; do
    # Start of application_repositories section
    if [[ "$line" =~ ^application_repositories: ]]; then
      in_repos=true
      continue
    fi
    # End of section (new top-level key)
    if $in_repos && [[ "$line" =~ ^[a-z_]+: ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
      break
    fi
    # Parse list item
    if $in_repos && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*[\"\']?([^\"\']+)[\"\']?$ ]]; then
      repo="${BASH_REMATCH[1]}"
      repo=$(echo "$repo" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ -n "$repo" ]; then
        ALL_REPOS+=("$repo")
      fi
    fi
  done < "$PROJECT_DIR/group_vars/all/vars.yml"
}

# =============================================================================
# Domains Configuration (loaded from vars.yml)
# =============================================================================

# Load domains into associative array
declare -A DOMAINS_CONFIG

load_domains() {
  local current_domain=""
  local in_domains=false
  while IFS= read -r line; do
    # Start of managed_domains section
    if [[ "$line" =~ ^managed_domains: ]]; then
      in_domains=true
      continue
    fi
    # End of section (new top-level key)
    if $in_domains && [[ "$line" =~ ^[a-z_]+: ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
      break
    fi
    # Parse domain name
    if $in_domains && [[ "$line" =~ name:[[:space:]]*[\"\']([^\"\']+)[\"\'] ]]; then
      current_domain="${BASH_REMATCH[1]}"
    fi
    # Parse records
    if $in_domains && [[ "$line" =~ records:[[:space:]]*[\"\']([^\"\']+)[\"\'] ]] && [ -n "$current_domain" ]; then
      DOMAINS_CONFIG["$current_domain"]="${BASH_REMATCH[1]}"
      current_domain=""
    fi
  done < "$PROJECT_DIR/group_vars/all/vars.yml"
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
  if ! gh auth status &> /dev/null; then
    echo -e "${RED}✗ GitHub CLI not authenticated. Run: gh auth login${NC}"
    return 1
  fi
  return 0
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
