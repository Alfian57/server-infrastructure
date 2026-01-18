#!/bin/bash

# =============================================================================
# Update Inventory to Use SSH Key with Deployer User
# =============================================================================
# Run this after successful bootstrap to switch from password to SSH key auth
#
# Configuration is loaded from group_vars/all/vars.yml
#
# This script:
#   1. Gets current IP from inventory
#   2. Updates inventory to use deployer user with SSH key
#   3. Tests the connection
# =============================================================================

set -e

# Load shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Get current VPS IP from inventory
VPS_IP=$(get_vps_ip)

if [ -z "$VPS_IP" ]; then
    echo -e "${RED}✗ Could not find VPS IP in inventory!${NC}"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Updating Inventory for SSH Key Authentication${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "VPS IP: $VPS_IP"
echo "User: $DEPLOY_USER"
echo "SSH Port: $SSH_PORT"
echo "SSH Key: $SSH_KEY_PATH"
echo ""

# Update inventory to use deployer user with SSH key
cat > "$PROJECT_DIR/inventory/hosts.ini" << EOF
[all]
${VPS_IP} ansible_user=${DEPLOY_USER} ansible_port=${SSH_PORT} ansible_ssh_private_key_file=${SSH_KEY_PATH}
EOF

echo -e "${GREEN}✓ Inventory updated!${NC}"
echo ""
echo "Testing SSH connection as $DEPLOY_USER..."
echo ""

# Check if vault password file exists and use it
VAULT_PASS="$PROJECT_DIR/.vault_pass"
if [ -f "$VAULT_PASS" ]; then
    ansible all -i "$PROJECT_DIR/inventory/hosts.ini" --vault-password-file="$VAULT_PASS" -m ping
else
    ansible all -i "$PROJECT_DIR/inventory/hosts.ini" -m ping
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ SSH Key Authentication Ready!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "Next step: make deploy"
echo ""
