#!/bin/bash

# =============================================================================
# Local Script: Update All Cloud Services
# =============================================================================
# This script runs all cloud service updates in sequence:
#   1. GitHub Repository Secrets
#   2. Cloudflare DNS Records
#
# Usage:
#   ./scripts/update-cloud-services.sh
#   ./scripts/update-cloud-services.sh -y  # Auto-confirm
#
# Or via Makefile:
#   make update-cloud
#   make update-cloud-y
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m'

# Parse arguments
AUTO_CONFIRM=""
if [[ "${1:-}" == "-y" ]] || [[ "${1:-}" == "--yes" ]]; then
  AUTO_CONFIRM="-y"
fi

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Update All Cloud Services${NC}                                    ${BLUE}║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Update GitHub Secrets
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Step 1/2: Updating GitHub Repository Secrets${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -n "$AUTO_CONFIRM" ]; then
  echo "y" | "$SCRIPT_DIR/update-github-secrets-local.sh"
else
  "$SCRIPT_DIR/update-github-secrets-local.sh"
fi

echo ""
echo -e "${GREEN}✓ GitHub Secrets update complete${NC}"
echo ""

# Step 2: Update Cloudflare DNS
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Step 2/2: Updating Cloudflare DNS Records${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -n "$AUTO_CONFIRM" ]; then
  "$SCRIPT_DIR/update-cloudflare-dns-local.sh" -y
else
  "$SCRIPT_DIR/update-cloudflare-dns-local.sh"
fi

echo ""
echo -e "${GREEN}✓ Cloudflare DNS update complete${NC}"
echo ""

# Summary
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}All Cloud Services Updated Successfully!${NC}                     ${BLUE}║${NC}"
echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  ✓ GitHub Repository Secrets                                  ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ✓ Cloudflare DNS Records                                     ${BLUE}║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
