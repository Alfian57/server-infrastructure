#!/bin/bash

# =============================================================================
# Local Script: Update GitHub Repository Secrets
# =============================================================================
# This script can be run locally (without deploying to server) to update
# GitHub secrets for all application repositories.
#
# Usage:
#   ./scripts/update-github-secrets-local.sh
#   ./scripts/update-github-secrets-local.sh materi-ku  # single repo
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# GitHub Owner
GITHUB_OWNER="alfian57"

# All repositories
ALL_REPOS=(
  "materi-ku"
  "panca-trivia"
  "ruang-istirahat"
  "tech-talk"
  "posyandu"
  "solvo"
  "Presensi-Skansaba-Web"
  "campus-project-hub-api"
  "ruang-tenang-api"
  "campus-project-hub-web"
  "personal-portofolio"
  "ruang-tenang-web"
  "file-pod-api"
)

# Get values from local files
get_vps_host() {
  grep -v "^#" "$PROJECT_DIR/inventory/hosts.ini" | grep -v "^\[" | grep -v "^$" | head -1 | awk '{print $1}'
}

get_github_token() {
  ansible-vault view "$PROJECT_DIR/group_vars/all/vault.yml" --vault-password-file="$PROJECT_DIR/.vault_pass" 2>/dev/null | grep "vault_github_token:" | awk '{print $2}' | tr -d '"'
}

print_header() {
  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║${NC}  ${GREEN}Update GitHub Repository Secrets (Local)${NC}                   ${BLUE}║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

update_repo_secrets() {
  local repo=$1
  local full_repo="${GITHUB_OWNER}/${repo}"
  
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Repository: ${full_repo}${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  # Check if repo exists
  if ! gh repo view "$full_repo" &> /dev/null; then
    echo -e "${YELLOW}⚠ Repository not found: $full_repo (skipping)${NC}"
    return 1
  fi
  
  local vps_host=$(get_vps_host)
  local vps_user="deployer"
  local vps_ssh_port="22"
  local vps_key=$(cat ~/.ssh/server_ed25519)
  local docker_token=$(get_github_token)
  
  # Update secrets
  echo "$vps_host" | gh secret set VPS_HOST --repo "$full_repo" && echo -e "${GREEN}✓${NC} VPS_HOST"
  echo "$vps_user" | gh secret set VPS_USER --repo "$full_repo" && echo -e "${GREEN}✓${NC} VPS_USER"
  echo "$vps_ssh_port" | gh secret set VPS_SSH_PORT --repo "$full_repo" && echo -e "${GREEN}✓${NC} VPS_SSH_PORT"
  echo "$vps_key" | gh secret set VPS_KEY --repo "$full_repo" && echo -e "${GREEN}✓${NC} VPS_KEY"
  echo "$docker_token" | gh secret set DOCKER_TOKEN --repo "$full_repo" && echo -e "${GREEN}✓${NC} DOCKER_TOKEN"
  
  echo ""
  return 0
}

# Main
print_header

# Check gh CLI
if ! command -v gh &> /dev/null; then
  echo -e "${RED}✗ GitHub CLI (gh) not installed${NC}"
  exit 1
fi

if ! gh auth status &> /dev/null; then
  echo -e "${RED}✗ GitHub CLI not authenticated. Run: gh auth login${NC}"
  exit 1
fi
echo -e "${GREEN}✓ GitHub CLI authenticated${NC}"

# Check required files
if [ ! -f "$PROJECT_DIR/.vault_pass" ]; then
  echo -e "${RED}✗ .vault_pass not found${NC}"
  exit 1
fi

if [ ! -f ~/.ssh/server_ed25519 ]; then
  echo -e "${RED}✗ SSH key not found at ~/.ssh/server_ed25519${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Required files found${NC}"
echo ""

# Determine repos to update
if [ $# -gt 0 ]; then
  REPOS=("$@")
else
  REPOS=("${ALL_REPOS[@]}")
fi

echo -e "${BLUE}Repositories to update:${NC}"
for repo in "${REPOS[@]}"; do
  echo "  - ${GITHUB_OWNER}/${repo}"
done
echo ""

read -p "Continue? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

# Update each repo
success=0
failed=0

for repo in "${REPOS[@]}"; do
  if update_repo_secrets "$repo"; then
    ((success++))
  else
    ((failed++))
  fi
done

# Summary
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Summary${NC}                                                      ${BLUE}║${NC}"
echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  Total: ${#REPOS[@]}  |  ${GREEN}Success: $success${NC}  |  ${RED}Failed: $failed${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
