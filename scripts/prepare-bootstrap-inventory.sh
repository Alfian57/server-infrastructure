#!/bin/bash

# =============================================================================
# Prepare Bootstrap Inventory
# =============================================================================
# Creates inventory/hosts.ini for the first connection to a VPS.
# Supports providers that start with password auth and providers that start with
# SSH private/public key auth.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

read_default() {
  local prompt=$1
  local default=$2
  local value

  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " value
    echo "${value:-$default}"
  else
    read -r -p "$prompt: " value
    echo "$value"
  fi
}

current_host="$(get_vps_ip || true)"
current_user="$(awk 'NF && $1 !~ /^\[/ {for (i=1;i<=NF;i++) if ($i ~ /^ansible_user=/) {split($i,a,"="); print a[2]; exit}}' "$PROJECT_DIR/inventory/hosts.ini" 2>/dev/null || true)"
current_port="$(awk 'NF && $1 !~ /^\[/ {for (i=1;i<=NF;i++) if ($i ~ /^ansible_port=/) {split($i,a,"="); print a[2]; exit}}' "$PROJECT_DIR/inventory/hosts.ini" 2>/dev/null || true)"

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Prepare Bootstrap Inventory${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

vps_host="$(read_default "VPS IP/host" "$current_host")"
bootstrap_user="$(read_default "Initial SSH user" "${current_user:-root}")"
bootstrap_port="$(read_default "SSH port" "${current_port:-$SSH_PORT}")"

echo ""
echo "Initial authentication method:"
echo "  1) password"
echo "  2) private key"
read -r -p "Choose [1]: " auth_choice
auth_choice="${auth_choice:-1}"

inventory_line="${vps_host} ansible_user=${bootstrap_user} ansible_port=${bootstrap_port}"
bootstrap_command="ansible-playbook playbooks/bootstrap-ssh.yml -i inventory/hosts.ini --ask-pass"

case "$auth_choice" in
  1|password|Password)
    echo ""
    echo -e "${YELLOW}Password is not written to inventory. Ansible will prompt for it.${NC}"
    ;;
  2|key|private-key|Private-key)
    bootstrap_key="$(read_default "Initial private key path" "$SSH_KEY_PATH")"
    inventory_line="${inventory_line} ansible_ssh_private_key_file=${bootstrap_key}"
    bootstrap_command="ansible-playbook playbooks/bootstrap-ssh.yml -i inventory/hosts.ini"
    ;;
  *)
    echo -e "${RED}✗ Invalid authentication method: $auth_choice${NC}"
    exit 1
    ;;
esac

cat > "$PROJECT_DIR/inventory/hosts.ini" << EOF
[all]
${inventory_line}
EOF

echo ""
echo -e "${GREEN}✓ inventory/hosts.ini prepared for bootstrap${NC}"
echo ""
echo "Next command:"
echo "  $bootstrap_command"
echo ""
