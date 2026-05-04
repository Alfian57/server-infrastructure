#!/bin/bash

# =============================================================================
# Local Script: Check Cloud Services Status
# =============================================================================
# Verifies that GitHub secrets and Cloudflare DNS are properly configured
#
# Configuration is loaded from group_vars/all/vars.yml
#
# Usage:
#   ./scripts/check-cloud-services.sh
#
# Or via Makefile:
#   make check-cloud
# =============================================================================

set -e

# Load shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Disable strict mode for counting logic
set +e

# Expected secrets for each repository
EXPECTED_SECRETS=("VPS_HOST" "VPS_USER" "VPS_SSH_PORT" "VPS_KEY" "DOCKER_TOKEN")

# Repositories to check, loaded from the central app catalog.
CHECK_REPOS=("${ALL_REPOS[@]}")

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Check Cloud Services Status${NC}                                  ${BLUE}║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check requirements
if ! check_requirements; then
  exit 1
fi

if ! check_gh_auth; then
  exit 1
fi

echo -e "${GREEN}✓ Requirements met${NC}"
echo ""

# Show loaded configuration
echo -e "${BLUE}Configuration loaded from vars.yml:${NC}"
echo "  GitHub Owner: $GITHUB_OWNER"
echo "  Primary Domain: $PRIMARY_DOMAIN"
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

for repo in "${CHECK_REPOS[@]}"; do
  full_repo="${repo}"
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

for domain in "${!DOMAINS_CONFIG[@]}"; do
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

  for record in ${DOMAINS_CONFIG[$domain]}; do
    if [ "$record" = "@" ]; then
      fqdn="$domain"
    elif [ "$record" = "*" ]; then
      fqdn="*.$domain"
    else
      fqdn="$record.$domain"
    fi

    record_info=$(echo "$records" | jq -r --arg name "$fqdn" '.result[] | select(.name == $name) | "\(.content)\t\(.proxied)"' | head -1)
    record_ip=$(printf '%s' "$record_info" | awk -F '\t' '{print $1}')
    record_proxied=$(printf '%s' "$record_info" | awk -F '\t' '{print $2}')

    if [ "$record_ip" = "$VPS_IP" ]; then
      echo -e "  ${GREEN}✓${NC} $fqdn → $record_ip (proxied: $record_proxied)"
      ((dns_ok++))
    elif [ -n "$record_ip" ]; then
      echo -e "  ${RED}✗${NC} $fqdn → $record_ip (expected: $VPS_IP)"
      ((dns_fail++))
    else
      echo -e "  ${RED}✗${NC} $fqdn (missing A record)"
      ((dns_fail++))
    fi
  done
  
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
