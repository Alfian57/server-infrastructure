#!/bin/bash
# ============================================================================
# Script: trigger-github-actions-local.sh
# Description: Trigger GitHub Actions workflows for all repositories
# Usage: ./scripts/trigger-github-actions-local.sh [--dry-run]
# ============================================================================
# This script runs LOCALLY on developer machine or CI runner.
# It uses GitHub CLI (gh) authenticated on the local machine.
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared configuration
source "$SCRIPT_DIR/config.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check requirements
check_requirements "gh"
check_files "vars"

# Validate GitHub CLI authentication
if ! check_gh_auth; then
  exit 1
fi

# Load repositories from config
load_repositories

# Parse arguments
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Workflow mappings are loaded from the central app catalog.
declare -A WORKFLOW_FILES
while IFS=$'\t' read -r repo workflow; do
  [ -n "$repo" ] && WORKFLOW_FILES["$repo"]="$workflow"
done < <("$PROJECT_DIR/scripts/app-catalog.py" workflows)

DEFAULT_BRANCH="main"
TRIGGER_DELAY=3

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}⚡ Triggering GitHub Actions for ${#ALL_REPOS[@]} repositories${NC}"
if $DRY_RUN; then
  echo -e "${YELLOW}   (DRY RUN - no actual triggers)${NC}"
fi
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Track results
declare -a SUCCESS_REPOS=()
declare -a FAILED_REPOS=()
declare -a SKIPPED_REPOS=()

for repo in "${ALL_REPOS[@]}"; do
  full_repo="$repo"
  workflow="${WORKFLOW_FILES[$full_repo]:-build-and-deploy.yml}"
  
  echo -e "${BLUE}→${NC} $full_repo ($workflow)"
  
  if $DRY_RUN; then
    echo -e "  ${YELLOW}[DRY RUN]${NC} Would trigger: gh workflow run $workflow -R $full_repo --ref $DEFAULT_BRANCH"
    SUCCESS_REPOS+=("$full_repo")
    continue
  fi
  
  # Check if workflow exists
  if ! gh workflow view "$workflow" -R "$full_repo" &>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC} Workflow not found, skipping"
    SKIPPED_REPOS+=("$full_repo")
    continue
  fi
  
  # Trigger the workflow
  if gh workflow run "$workflow" -R "$full_repo" --ref "$DEFAULT_BRANCH" 2>&1; then
    echo -e "  ${GREEN}✓${NC} Triggered successfully"
    SUCCESS_REPOS+=("$full_repo")
  else
    echo -e "  ${RED}✗${NC} Failed to trigger"
    FAILED_REPOS+=("$full_repo")
  fi
  
  # Small delay between triggers to avoid rate limiting
  sleep $TRIGGER_DELAY
done

# Summary
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}📊 GitHub Actions Trigger Summary${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}"

if [[ ${#SUCCESS_REPOS[@]} -gt 0 ]]; then
  echo -e "${GREEN}✓ Triggered (${#SUCCESS_REPOS[@]}):${NC}"
  for repo in "${SUCCESS_REPOS[@]}"; do
    echo -e "  - $repo"
  done
fi

if [[ ${#SKIPPED_REPOS[@]} -gt 0 ]]; then
  echo -e "${YELLOW}⚠ Skipped (${#SKIPPED_REPOS[@]}):${NC}"
  for repo in "${SKIPPED_REPOS[@]}"; do
    echo -e "  - $repo"
  done
fi

if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then
  echo -e "${RED}✗ Failed (${#FAILED_REPOS[@]}):${NC}"
  for repo in "${FAILED_REPOS[@]}"; do
    echo -e "  - $repo"
  done
fi

echo ""
echo -e "${BLUE}🔗 Check workflow status at:${NC}"
for repo in "${ALL_REPOS[@]}"; do
  echo -e "  - https://github.com/$repo/actions"
done
echo ""

# Exit with error if any failed
if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then
  exit 1
fi
