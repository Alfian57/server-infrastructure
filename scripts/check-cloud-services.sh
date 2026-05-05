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
echo -e "${YELLOW}Checking GitHub Repository Secrets and Variables${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

github_ok=1
github_fail=0
if ! "$PROJECT_DIR/scripts/env-contracts.py" github-check; then
  github_ok=0
  github_fail=1
fi
echo ""

# ═══════════════════════════════════════════════════════════
# Check Cloudflare DNS
# ═══════════════════════════════════════════════════════════
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Checking Cloudflare DNS Records${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

CF_CREDENTIAL=$(get_cf_token)
CF_EMAIL=$(get_cf_email)
export CF_CREDENTIAL
export CF_EMAIL

if [ -z "$CF_CREDENTIAL" ]; then
  echo -e "${RED}✗ Failed to get Cloudflare credential from vault_cloudflare_api_token${NC}"
  exit 1
fi

if ! CF_AUTH_TYPE=$(detect_cloudflare_auth "$CF_CREDENTIAL"); then
  echo -e "${RED}✗ Cloudflare credential is invalid${NC}"
  echo "  Use either API Token, or Global API Key plus vault_cloudflare_email."
  exit 1
fi
export CF_AUTH_TYPE

if [ "$CF_AUTH_TYPE" = "global_key" ]; then
  echo -e "${GREEN}✓ Cloudflare Global API Key verified${NC}"
else
  echo -e "${GREEN}✓ Cloudflare API Token verified${NC}"
fi
echo ""

dns_ok=0
dns_fail=0

for domain in "${!DOMAINS_CONFIG[@]}"; do
  echo -e "${BLUE}Domain: ${domain}${NC}"
  
  # Get zone ID
  zone_id=$(cloudflare_request GET "https://api.cloudflare.com/client/v4/zones?name=${domain}" | jq -r '.result[0].id // empty')
  
  if [ -z "$zone_id" ]; then
    echo -e "  ${YELLOW}⚠${NC} Domain not found in Cloudflare (skipping)"
    echo ""
    continue
  fi
  
  # Get A records
  records=$(cloudflare_request GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=A")

  record_list=()
  read -r -a record_list <<< "${DOMAINS_CONFIG[$domain]}"
  for record in "${record_list[@]}"; do
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
echo -e "${BLUE}║${NC}  GitHub Catalog Check: ${GREEN}${github_ok} OK${NC} / ${RED}${github_fail} Failed${NC}                      ${BLUE}║${NC}"
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
