#!/bin/bash

# =============================================================================
# Local Script: Update GitHub Repository Secrets
# =============================================================================
# This script can be run locally (without deploying to server) to update
# GitHub secrets for all application repositories.
#
# Configuration is loaded from group_vars/all/vars.yml
#
# Usage:
#   ./scripts/update-github-secrets-local.sh
#   ./scripts/update-github-secrets-local.sh materi-ku  # single repo
# =============================================================================

# Don't use set -e - we want to continue on errors
set +e

# Load shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

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
  
  local vps_host=$(get_vps_ip)
  local vps_user="$DEPLOY_USER"
  local vps_ssh_port="$SSH_PORT"
  local vps_key=$(cat "$SSH_KEY_PATH")
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

# Update repository variables (for mobile apps that need config via variables)
update_repo_variables() {
  local repo=$1
  local full_repo="${GITHUB_OWNER}/${repo}"
  
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Repository Variables: ${full_repo}${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  # Check if repo exists
  if ! gh repo view "$full_repo" &> /dev/null; then
    echo -e "${YELLOW}⚠ Repository not found: $full_repo (skipping)${NC}"
    return 1
  fi
  
  # Handle specific repos that need variables
  case "$repo" in
    "file-pod-mobile")
      local base_url="https://file-pod-api.alfian-gading.site"
      gh variable set BASE_URL --repo "$full_repo" --body "$base_url" && echo -e "${GREEN}✓${NC} BASE_URL = $base_url"
      ;;
    *)
      echo -e "${YELLOW}⚠ No variables configured for $repo${NC}"
      ;;
  esac
  
  echo ""
  return 0
}

# Main
print_header

# Check requirements
if ! check_requirements; then
  exit 1
fi

if ! check_gh_auth; then
  exit 1
fi
echo -e "${GREEN}✓ GitHub CLI authenticated${NC}"

if ! check_files; then
  exit 1
fi
echo -e "${GREEN}✓ Required files found${NC}"
echo ""

# Show loaded configuration
echo -e "${BLUE}Configuration loaded from vars.yml:${NC}"
echo "  GitHub Owner: $GITHUB_OWNER"
echo "  Deploy User: $DEPLOY_USER"
echo "  SSH Port: $SSH_PORT"
echo "  SSH Key: $SSH_KEY_PATH"
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

# Update each repo secrets
success=0
failed=0

for repo in "${REPOS[@]}"; do
  if update_repo_secrets "$repo"; then
    ((success++))
  else
    ((failed++))
  fi
done

# Also update repository variables for mobile apps
# These are repos that aren't in the main deploy list but need GitHub variables
MOBILE_REPOS=("file-pod-mobile")
echo ""
echo -e "${BLUE}Updating GitHub Repository Variables for Mobile Apps...${NC}"
echo ""
for repo in "${MOBILE_REPOS[@]}"; do
  update_repo_variables "$repo" || true
done

# Summary
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Summary${NC}                                                      ${BLUE}║${NC}"
echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  Total: ${#REPOS[@]}  |  ${GREEN}Success: $success${NC}  |  ${RED}Failed: $failed${NC}              ${BLUE}║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
