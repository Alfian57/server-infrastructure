#!/bin/bash

# =============================================================================
# Local Script: Check Cloud Services Status
# =============================================================================
# Verifies that GitHub secrets and Cloudflare DNS are properly configured
#
# Usage:
#   ./scripts/check-cloud-services.sh
#
# Or via Makefile:
#   make check-cloud
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m'

# GitHub Owner
GITHUB_OWNER="alfian57"

# Repositories to check
REPOS=(
  "materi-ku"
  "panca-trivia"
  "tech-talk"
)

# Expected secrets
EXPECTED_SECRETS=("VPS_HOST" "VPS_USER" "VPS_SSH_PORT" "VPS_KEY" "DOCKER_TOKEN")

# Domains to check
DOMAINS=("alfian-gading.site" "solvo-tech.site" "ruang-tenang.site")

# Get VPS IP
get_vps_ip() {
  grep -v "^#" "$PROJECT_DIR/inventory/hosts.ini" | grep -v "^\[" | grep -v "^$" | head -1 | awk '{print $1}'
}

# Get Cloudflare token
get_cf_token() {
  ansible-vault view "$PROJECT_DIR/group_vars/all/vault.yml" --vault-password-file="$PROJECT_DIR/.vault_pass" 2>/dev/null | grep "vault_cloudflare_api_token:" | awk '{print $2}' | tr -d '"'
}

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Check Cloud Services Status${NC}                                  ${BLUE}║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check requirements
if ! command -v gh &> /dev/null; then
  echo -e "${RED}✗ GitHub CLI (gh) not installed${NC}"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo -e "${RED}✗ jq not installed${NC}"
  exit 1
fi

if ! gh auth status &> /dev/null; then
  echo -e "${RED}✗ GitHub CLI not authenticated${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Requirements met${NC}"
echo ""

VPS_IP=$(get_vps_ip)
echo -e "${BLUE}Expected VPS IP: ${VPS_IP}${NC}"
echo ""

# ═══════════════════════════════════════════════════════════
# Check GitHub Secrets
# ═══════════════════════════════════════════════════════════
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Checking GitHub Repository Secrets${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

github_ok=0
github_fail=0

for repo in "${REPOS[@]}"; do
  full_repo="${GITHUB_OWNER}/${repo}"
  echo -e "${BLUE}Repository: ${full_repo}${NC}"
  
  # Get secrets list
  secrets=$(gh secret list --repo "$full_repo" 2>/dev/null | awk '{print $1}')
  
  all_found=true
  for expected in "${EXPECTED_SECRETS[@]}"; do
    if echo "$secrets" | grep -q "^${expected}$"; then
      echo -e "  ${GREEN}✓${NC} $expected"
    else
      echo -e "  ${RED}✗${NC} $expected (missing)"
      all_found=false
    fi
  done
  
  if [ "$all_found" = true ]; then
    ((github_ok++))
  else
    ((github_fail++))
  fi
  echo ""
done

# ═══════════════════════════════════════════════════════════
# Check Cloudflare DNS
# ═══════════════════════════════════════════════════════════
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Checking Cloudflare DNS Records${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

CF_TOKEN=$(get_cf_token)

dns_ok=0
dns_fail=0

for domain in "${DOMAINS[@]}"; do
  echo -e "${BLUE}Domain: ${domain}${NC}"
  
  # Get zone ID
  zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${domain}" \
    -H "Authorization: Bearer $CF_TOKEN" | jq -r '.result[0].id // empty')
  
  if [ -z "$zone_id" ]; then
    echo -e "  ${YELLOW}⚠${NC} Domain not found in Cloudflare (skipping)"
    echo ""
    continue
  fi
  
  # Get A records
  records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=A" \
    -H "Authorization: Bearer $CF_TOKEN")
  
  # Check root domain
  root_ip=$(echo "$records" | jq -r --arg name "$domain" '.result[] | select(.name == $name) | .content')
  
  if [ "$root_ip" == "$VPS_IP" ]; then
    echo -e "  ${GREEN}✓${NC} $domain → $root_ip"
    ((dns_ok++))
  elif [ -n "$root_ip" ]; then
    echo -e "  ${RED}✗${NC} $domain → $root_ip (expected: $VPS_IP)"
    ((dns_fail++))
  else
    echo -e "  ${YELLOW}⚠${NC} $domain (no A record)"
  fi
  
  # Check subdomains count
  subdomain_count=$(echo "$records" | jq '[.result[] | select(.name != "'"$domain"'")] | length')
  echo -e "  ${GREEN}✓${NC} $subdomain_count subdomain records configured"
  
  echo ""
done

# ═══════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Summary${NC}                                                      ${BLUE}║${NC}"
echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  GitHub Repositories: ${GREEN}${github_ok} OK${NC} / ${RED}${github_fail} Failed${NC}                      ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  Cloudflare Domains:  ${GREEN}${dns_ok} OK${NC} / ${RED}${dns_fail} Failed${NC}                       ${BLUE}║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $github_fail -gt 0 ] || [ $dns_fail -gt 0 ]; then
  echo -e "${YELLOW}⚠ Some checks failed. Run:${NC}"
  echo "  make update-cloud"
  exit 1
else
  echo -e "${GREEN}✓ All cloud services are properly configured!${NC}"
fi
