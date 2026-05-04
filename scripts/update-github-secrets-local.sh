#!/bin/bash

# =============================================================================
# Local Script: Update GitHub Repository Secrets and Variables
# =============================================================================
# Values are resolved from group_vars/all/apps.yml, vars.yml, inventory, and
# encrypted vault.yml. Secret values are piped to gh and are never printed.
#
# Usage:
#   ./scripts/update-github-secrets-local.sh
#   ./scripts/update-github-secrets-local.sh -y
#   ./scripts/update-github-secrets-local.sh --dry-run
#   ./scripts/update-github-secrets-local.sh materi-ku
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

AUTO_CONFIRM=false
DRY_RUN=false
REPOS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)
      AUTO_CONFIRM=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    *)
      REPOS+=("$1")
      ;;
  esac
  shift
done

print_header() {
  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║${NC}  ${GREEN}Update GitHub Secrets and Variables (Local)${NC}                  ${BLUE}║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

print_header

if ! check_requirements; then
  exit 1
fi

if [ "$DRY_RUN" != true ] && ! check_gh_auth; then
  exit 1
fi

if ! check_files; then
  exit 1
fi

echo -e "${GREEN}✓ Requirements met${NC}"
echo ""
echo -e "${BLUE}Configuration loaded:${NC}"
echo "  GitHub Owner: $GITHUB_OWNER"
echo "  Ansible User: $DEPLOY_USER"
echo "  GitHub Actions User: ${CI_DEPLOY_USER:-$DEPLOY_USER}"
echo "  SSH Port: $SSH_PORT"
echo "  SSH Key: $SSH_KEY_PATH"
echo ""

if [ ${#REPOS[@]} -eq 0 ]; then
  REPOS=("${ALL_REPOS[@]}")
fi

echo -e "${BLUE}Repositories to update:${NC}"
for repo in "${REPOS[@]}"; do
  echo "  - ${repo}"
done
echo ""

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}Dry run mode: no GitHub values will be changed.${NC}"
  echo ""
fi

if [ "$AUTO_CONFIRM" != true ]; then
  read -p "Continue? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

SYNC_ARGS=()
if [ "$DRY_RUN" = true ]; then
  SYNC_ARGS+=("--dry-run")
fi
for repo in "${REPOS[@]}"; do
  SYNC_ARGS+=("--repo" "$repo")
done

"$PROJECT_DIR/scripts/env-contracts.py" github-sync "${SYNC_ARGS[@]}"
