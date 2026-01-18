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
if ! gh auth status &>/dev/null; then
  echo -e "${RED}✗ GitHub CLI not authenticated. Run: gh auth login${NC}"
  exit 1
fi

# Load repositories from config
load_repositories

# Parse arguments
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Define workflow mappings (repo -> workflow file)
# These match the defaults from the old Ansible role
declare -A WORKFLOW_FILES=(
  ["materi-ku"]="build-and-deploy.yml"
  ["panca-trivia"]="build-and-deploy.yml"
  ["posyandu"]="build-and-deploy.yml"
  ["ruang-istirahat"]="build-and-deploy.yml"
  ["solvo"]="build-and-deploy.yml"
  ["tech-talk"]="built-and-deploy.yml"
  ["Presensi-Skansaba-Web"]="build-and-deploy.yml"
  ["ruang-tenang-api"]="build-and-deploy.yml"
  ["campus-project-hub-api"]="docker-build.yml"
  ["file-pod-api"]="build-and-deploy.yml"
  ["ruang-tenang-web"]="build-and-deploy.yml"
  ["personal-portofolio"]="build-and-deploy.yml"
  ["campus-project-hub-web"]="docker-build.yml"
)

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
  full_repo="$GITHUB_OWNER/$repo"
  workflow="${WORKFLOW_FILES[$repo]:-build-and-deploy.yml}"
  
  echo -e "${BLUE}→${NC} $full_repo ($workflow)"
  
  if $DRY_RUN; then
    echo -e "  ${YELLOW}[DRY RUN]${NC} Would trigger: gh workflow run $workflow -R $full_repo --ref $DEFAULT_BRANCH"
    SUCCESS_REPOS+=("$repo")
    continue
  fi
  
  # Check if workflow exists
  if ! gh workflow view "$workflow" -R "$full_repo" &>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC} Workflow not found, skipping"
    SKIPPED_REPOS+=("$repo")
    continue
  fi
  
  # Trigger the workflow
  if gh workflow run "$workflow" -R "$full_repo" --ref "$DEFAULT_BRANCH" 2>&1; then
    echo -e "  ${GREEN}✓${NC} Triggered successfully"
    SUCCESS_REPOS+=("$repo")
  else
    echo -e "  ${RED}✗${NC} Failed to trigger"
    FAILED_REPOS+=("$repo")
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
  echo -e "  - https://github.com/$GITHUB_OWNER/$repo/actions"
done
echo ""

# Exit with error if any failed
if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then
  exit 1
fi
