#!/bin/bash

# =============================================================================
# Local Script: Update Cloudflare DNS Records
# =============================================================================
# This script can be run locally (without deploying to server) to update
# Cloudflare DNS records for all domains.
#
# Usage:
#   ./scripts/update-cloudflare-dns-local.sh
#   ./scripts/update-cloudflare-dns-local.sh --domain alfian-gading.site  # single domain
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

# Get VPS IP from inventory
get_vps_ip() {
  grep -v "^#" "$PROJECT_DIR/inventory/hosts.ini" | grep -v "^\[" | grep -v "^$" | head -1 | awk '{print $1}'
}

# Get Cloudflare API token from vault
get_cf_token() {
  ansible-vault view "$PROJECT_DIR/group_vars/all/vault.yml" --vault-password-file="$PROJECT_DIR/.vault_pass" 2>/dev/null | grep "vault_cloudflare_api_token:" | awk '{print $2}' | tr -d '"'
}

print_header() {
  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║${NC}  ${GREEN}Update Cloudflare DNS Records (Local)${NC}                      ${BLUE}║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

# All domains and their records
declare -A DOMAINS
DOMAINS["alfian-gading.site"]="@ materi-ku panca-trivia ruang-istirahat tech-talk posyandu presensi-skansaba-web campus-project-hub-api campus-project-hub-web file-pod-api *"
DOMAINS["solvo-tech.site"]="@"
DOMAINS["ruang-tenang.site"]="@ api"

# Records that should NOT be proxied
NON_PROXIED="*"

update_dns_record() {
  local zone_id=$1
  local domain=$2
  local name=$3
  local vps_ip=$4
  local cf_token=$5
  
  # Build full name
  if [ "$name" == "@" ]; then
    full_name="$domain"
    api_name="$domain"
  elif [ "$name" == "*" ]; then
    full_name="*.$domain"
    api_name="*"
  else
    full_name="$name.$domain"
    api_name="$name"
  fi
  
  # Determine if proxied
  local proxied="true"
  if [[ "$NON_PROXIED" == *"$name"* ]]; then
    proxied="false"
  fi
  
  # Check if record exists
  local existing=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?name=${full_name}&type=A" \
    -H "Authorization: Bearer $cf_token" | jq -r '.result[0].id // empty')
  
  if [ -n "$existing" ]; then
    # Update existing record
    local result=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${existing}" \
      -H "Authorization: Bearer $cf_token" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$api_name\",\"content\":\"$vps_ip\",\"proxied\":$proxied,\"comment\":\"Updated by local script\"}")
    
    if [ "$(echo "$result" | jq -r '.success')" == "true" ]; then
      echo -e "${GREEN}✓${NC} Updated: $full_name → $vps_ip (proxied: $proxied)"
    else
      echo -e "${RED}✗${NC} Failed to update: $full_name"
      echo "  Error: $(echo "$result" | jq -r '.errors[0].message // "Unknown error"')"
      return 1
    fi
  else
    # Create new record
    local result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
      -H "Authorization: Bearer $cf_token" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$api_name\",\"content\":\"$vps_ip\",\"proxied\":$proxied,\"comment\":\"Created by local script\"}")
    
    if [ "$(echo "$result" | jq -r '.success')" == "true" ]; then
      echo -e "${GREEN}✓${NC} Created: $full_name → $vps_ip (proxied: $proxied)"
    else
      echo -e "${RED}✗${NC} Failed to create: $full_name"
      echo "  Error: $(echo "$result" | jq -r '.errors[0].message // "Unknown error"')"
      return 1
    fi
  fi
  
  return 0
}

update_domain() {
  local domain=$1
  local records=$2
  local vps_ip=$3
  local cf_token=$4
  
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Domain: ${domain}${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  # Get zone ID
  local zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${domain}" \
    -H "Authorization: Bearer $cf_token" | jq -r '.result[0].id // empty')
  
  if [ -z "$zone_id" ]; then
    echo -e "${YELLOW}⚠${NC} Domain not found in Cloudflare: $domain (skipping)"
    echo ""
    return 1
  fi
  
  echo "Zone ID: $zone_id"
  echo ""
  
  local success=0
  local failed=0
  
  for name in $records; do
    if update_dns_record "$zone_id" "$domain" "$name" "$vps_ip" "$cf_token"; then
      ((success++))
    else
      ((failed++))
    fi
  done
  
  echo ""
  echo "  Records: $success success, $failed failed"
  echo ""
  
  return 0
}

# Main
print_header

# Check requirements
if ! command -v jq &> /dev/null; then
  echo -e "${RED}✗ jq not installed. Install with: sudo apt install jq${NC}"
  exit 1
fi

if ! command -v curl &> /dev/null; then
  echo -e "${RED}✗ curl not installed${NC}"
  exit 1
fi

if [ ! -f "$PROJECT_DIR/.vault_pass" ]; then
  echo -e "${RED}✗ .vault_pass not found${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Requirements met${NC}"

# Get credentials
vps_ip=$(get_vps_ip)
cf_token=$(get_cf_token)

if [ -z "$cf_token" ]; then
  echo -e "${RED}✗ Failed to get Cloudflare API token from vault${NC}"
  exit 1
fi

echo -e "${GREEN}✓ VPS IP: $vps_ip${NC}"
echo -e "${GREEN}✓ Cloudflare token loaded${NC}"
echo ""

# Verify token
token_check=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $cf_token" | jq -r '.success')

if [ "$token_check" != "true" ]; then
  echo -e "${RED}✗ Cloudflare API token is invalid${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Cloudflare API token verified${NC}"
echo ""

# Parse arguments
SINGLE_DOMAIN=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --domain|-d)
      SINGLE_DOMAIN="$2"
      shift 2
      ;;
    -y|--yes)
      AUTO_CONFIRM=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Determine domains to update
if [ -n "$SINGLE_DOMAIN" ]; then
  if [ -z "${DOMAINS[$SINGLE_DOMAIN]}" ]; then
    echo -e "${RED}✗ Unknown domain: $SINGLE_DOMAIN${NC}"
    echo "Available domains: ${!DOMAINS[@]}"
    exit 1
  fi
  echo -e "${BLUE}Updating single domain: $SINGLE_DOMAIN${NC}"
else
  echo -e "${BLUE}Updating all domains:${NC}"
  for domain in "${!DOMAINS[@]}"; do
    echo "  - $domain"
  done
fi
echo ""

if [ "$AUTO_CONFIRM" != "true" ]; then
  read -p "Continue? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi
echo ""

# Update domains
if [ -n "$SINGLE_DOMAIN" ]; then
  update_domain "$SINGLE_DOMAIN" "${DOMAINS[$SINGLE_DOMAIN]}" "$vps_ip" "$cf_token"
else
  for domain in "${!DOMAINS[@]}"; do
    update_domain "$domain" "${DOMAINS[$domain]}" "$vps_ip" "$cf_token"
  done
fi

# Summary
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Cloudflare DNS Update Complete${NC}                               ${BLUE}║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "DNS propagation may take a few minutes."
echo "Verify at: https://dash.cloudflare.com/"
