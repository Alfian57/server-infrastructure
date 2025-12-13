#!/bin/bash

# =============================================================================
# Update Inventory to Use SSH Key
# =============================================================================
# Run this after successful bootstrap to switch from password to SSH key auth
# =============================================================================

set -e

INVENTORY_FILE="inventory/hosts.ini"
VPS_IP="103.47.225.241"
SSH_KEY_PATH="~/.ssh/server_ed25519"

echo "Updating inventory to use SSH key authentication..."

cat > "$INVENTORY_FILE" << EOF
[all]
${VPS_IP} ansible_user=root ansible_port=22 ansible_ssh_private_key_file=${SSH_KEY_PATH}
EOF

echo "✓ Inventory updated!"
echo ""
echo "Testing SSH connection..."
ansible all -i "$INVENTORY_FILE" -m ping

echo ""
echo "If successful, you can now run: make deploy"
