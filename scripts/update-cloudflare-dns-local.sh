#!/bin/bash

# =============================================================================
# Local Script: Update Cloudflare DNS Records
# =============================================================================
# This script can be run locally (without deploying to server) to update
# Cloudflare DNS records for all domains.
#
# Configuration is loaded from group_vars/all/vars.yml
#
# Usage:
#   ./scripts/update-cloudflare-dns-local.sh
#   ./scripts/update-cloudflare-dns-local.sh --domain alfian-gading.my.id
# =============================================================================

# Don't use set -e as we want to continue on errors
set +e

# Load shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

print_header() {
  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║${NC}  ${GREEN}Update Cloudflare DNS Records (Local)${NC}                      ${BLUE}║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

update_dns_record() {
  local zone_id=$1
  local domain=$2
  local name=$3
  local vps_ip=$4
  local full_name
  local api_name
  
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
  if [ "$name" = "*" ]; then
    proxied="false"
  fi
  
  # Check if record exists
  local existing
  existing=$(cloudflare_request GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?name=${full_name}&type=A" | jq -r '.result[0].id // empty')
  local payload
  payload=$(jq -cn \
    --arg name "$api_name" \
    --arg content "$vps_ip" \
    --arg comment "Managed by server-infra-with-ansible" \
    --argjson proxied "$proxied" \
    '{type:"A",name:$name,content:$content,proxied:$proxied,ttl:1,comment:$comment}')
  
  if [ "$DRY_RUN" = "true" ]; then
    if [ -n "$existing" ]; then
      echo -e "${YELLOW}[DRY RUN] Would update:${NC} $full_name → $vps_ip (proxied: $proxied)"
    else
      echo -e "${YELLOW}[DRY RUN] Would create:${NC} $full_name → $vps_ip (proxied: $proxied)"
    fi
    return 0
  fi

  if [ -n "$existing" ]; then
    # Update existing record
    local result
    result=$(cloudflare_request PUT "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${existing}" \
      -H "Content-Type: application/json" \
      --data "$payload")
    
    if [ "$(echo "$result" | jq -r '.success')" == "true" ]; then
      echo -e "${GREEN}✓${NC} Updated: $full_name → $vps_ip (proxied: $proxied)"
    else
      echo -e "${RED}✗${NC} Failed to update: $full_name"
      echo "  Error: $(echo "$result" | jq -r '.errors[0].message // "Unknown error"')"
      return 1
    fi
  else
    # Create new record
    local result
    result=$(cloudflare_request POST "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
      -H "Content-Type: application/json" \
      --data "$payload")
    
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

prune_obsolete_dns_records() {
  local zone_id=$1
  local domain=$2
  local records=$3
  
  # Build list of desired FQDNs
  local desired_fqdns=()
  local record_list=()
  read -r -a record_list <<< "$records"
  for name in "${record_list[@]}"; do
    if [ "$name" == "@" ]; then
      desired_fqdns+=("$domain")
    elif [ "$name" == "*" ]; then
      desired_fqdns+=("*.$domain")
    else
      desired_fqdns+=("$name.$domain")
    fi
  done

  echo -e "  ${BLUE}Auditing obsolete A/CNAME records in ${domain}...${NC}"

  local page=1
  local total_pages=1
  local pruned_count=0

  while [ "$page" -le "$total_pages" ]; do
    local response
    response=$(cloudflare_request GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?per_page=100&page=${page}")
    
    total_pages=$(echo "$response" | jq -r '.result_info.total_pages // 1' 2>/dev/null || echo 1)
    
    while IFS= read -r record; do
      [ -z "$record" ] && continue
      local id type name content
      id=$(echo "$record" | jq -r '.id')
      type=$(echo "$record" | jq -r '.type')
      name=$(echo "$record" | jq -r '.name')
      content=$(echo "$record" | jq -r '.content')

      # Safeguard: strictly ignore non-HTTP records (MX, TXT, SPF, DKIM, SRV, NS, SOA, CAA)
      if [ "$type" != "A" ] && [ "$type" != "CNAME" ]; then
        continue
      fi

      local is_desired=false
      for desired in "${desired_fqdns[@]}"; do
        if [ "${name,,}" = "${desired,,}" ]; then
          is_desired=true
          break
        fi
      done

      if [ "$is_desired" = "false" ]; then
        if [ "$DRY_RUN" = "true" ]; then
          echo -e "    ${YELLOW}[DRY RUN] Would delete obsolete record:${NC} $name ($type → $content)"
          ((pruned_count++))
        else
          local del_res
          del_res=$(cloudflare_request DELETE "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${id}")
          if [ "$(echo "$del_res" | jq -r '.success')" == "true" ]; then
            echo -e "    ${YELLOW}🗑 Deleted obsolete record:${NC} $name ($type → $content)"
            ((pruned_count++))
          else
            echo -e "    ${RED}✗ Failed to delete:${NC} $name - $(echo "$del_res" | jq -r '.errors[0].message // "Unknown error"')"
          fi
        fi
      fi
    done < <(echo "$response" | jq -c '.result[]?' 2>/dev/null)

    ((page++))
  done

  if [ "$pruned_count" -eq 0 ]; then
    echo -e "  ${GREEN}✓ No obsolete A/CNAME records found${NC}"
  else
    echo -e "  ${GREEN}✓ Audited and pruned $pruned_count obsolete record(s)${NC}"
  fi
}

update_domain() {
  local domain=$1
  local records=$2
  local vps_ip=$3
  
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Domain: ${domain}${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  # Get zone ID
  local zone_id
  zone_id=$(cloudflare_request GET "https://api.cloudflare.com/client/v4/zones?name=${domain}" | jq -r '.result[0].id // empty')
  
  if [ -z "$zone_id" ]; then
    echo -e "${YELLOW}⚠${NC} Domain not found in Cloudflare: $domain (skipping)"
    echo ""
    return 1
  fi
  
  echo "Zone ID: $zone_id"
  echo ""
  
  local success=0
  local failed=0
  
  local record_list=()
  read -r -a record_list <<< "$records"
  for name in "${record_list[@]}"; do
    if update_dns_record "$zone_id" "$domain" "$name" "$vps_ip"; then
      ((success++))
    else
      ((failed++))
    fi
  done
  
  echo ""
  echo "  Sync: $success success, $failed failed"
  echo ""

  # Prune obsolete A/CNAME records that are no longer declared in apps.yml
  prune_obsolete_dns_records "$zone_id" "$domain" "$records"
  echo ""
  
  if [ "$failed" -gt 0 ]; then
    return 1
  fi

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
CF_CREDENTIAL=$(get_cf_token)
CF_EMAIL=$(get_cf_email)
export CF_CREDENTIAL
export CF_EMAIL

if [ -z "$CF_CREDENTIAL" ]; then
  echo -e "${RED}✗ Failed to get Cloudflare credential from vault_cloudflare_api_token${NC}"
  exit 1
fi

echo -e "${GREEN}✓ VPS IP: $vps_ip${NC}"
echo -e "${GREEN}✓ Cloudflare credential loaded${NC}"
echo ""

if ! CF_AUTH_TYPE=$(detect_cloudflare_auth "$CF_CREDENTIAL"); then
  echo -e "${RED}✗ Cloudflare credential is invalid${NC}"
  echo "  Use either:"
  echo "  - API Token in vault_cloudflare_api_token, or"
  echo "  - Global API Key in vault_cloudflare_api_token plus vault_cloudflare_email"
  exit 1
fi
export CF_AUTH_TYPE

if [ "$CF_AUTH_TYPE" = "global_key" ]; then
  echo -e "${GREEN}✓ Cloudflare Global API Key verified${NC}"
else
  echo -e "${GREEN}✓ Cloudflare API Token verified${NC}"
fi
echo ""

# Show loaded configuration
echo -e "${BLUE}Domains loaded from apps.yml:${NC}"
for domain in "${!DOMAINS_CONFIG[@]}"; do
  echo "  - $domain"
done
echo ""

# Parse arguments
SINGLE_DOMAIN=""
AUTO_CONFIRM=""
DRY_RUN=""
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
    --dry-run)
      DRY_RUN=true
      AUTO_CONFIRM=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ "$DRY_RUN" = "true" ]; then
  echo -e "${YELLOW}Mode: DRY RUN (Simulating changes, no Cloudflare mutations will occur)${NC}"
  echo ""
fi

# Determine domains to update
if [ -n "$SINGLE_DOMAIN" ]; then
  if [ -z "${DOMAINS_CONFIG[$SINGLE_DOMAIN]}" ]; then
    echo -e "${RED}✗ Unknown domain: $SINGLE_DOMAIN${NC}"
    echo "Available domains: ${!DOMAINS_CONFIG[@]}"
    exit 1
  fi
  echo -e "${BLUE}Updating single domain: $SINGLE_DOMAIN${NC}"
else
  echo -e "${BLUE}Updating all domains...${NC}"
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
overall_failed=0
if [ -n "$SINGLE_DOMAIN" ]; then
  update_domain "$SINGLE_DOMAIN" "${DOMAINS_CONFIG[$SINGLE_DOMAIN]}" "$vps_ip" || overall_failed=1
else
  for domain in "${!DOMAINS_CONFIG[@]}"; do
    update_domain "$domain" "${DOMAINS_CONFIG[$domain]}" "$vps_ip" || overall_failed=1
  done
fi

# Summary
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Cloudflare DNS Update Complete${NC}                               ${BLUE}║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "DNS propagation may take a few minutes."
echo "Verify at: https://dash.cloudflare.com/"

if [ "$overall_failed" -ne 0 ]; then
  echo -e "${RED}✗ One or more DNS records failed to update${NC}"
  exit 1
fi
