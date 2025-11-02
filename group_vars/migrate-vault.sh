#!/bin/bash
# ============================================================================
# Vault Migration Script
# ============================================================================
# Script untuk migrate dari scattered vault files ke centralized group_vars
# 
# Usage:
#   chmod +x group_vars/migrate-vault.sh
#   ./group_vars/migrate-vault.sh
#
# What it does:
#   1. Backup all existing encrypted files
#   2. List all encrypted files found
#   3. Provide instructions for manual migration
#
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$PROJECT_ROOT/backup/vault-migration-$(date +%Y%m%d-%H%M%S)"
VAULT_FILE="$SCRIPT_DIR/all/vault.yml"

# ============================================================================
# Functions
# ============================================================================

print_header() {
    printf "\n${CYAN}═══════════════════════════════════════════════════════${NC}\n"
    printf "${GREEN}  Vault Migration Script${NC}\n"
    printf "${CYAN}═══════════════════════════════════════════════════════${NC}\n\n"
}

print_step() {
    printf "${BLUE}▶ %s${NC}\n" "$1"
}

print_success() {
    printf "${GREEN}✓ %s${NC}\n" "$1"
}

print_warning() {
    printf "${YELLOW}⚠ %s${NC}\n" "$1"
}

print_error() {
    printf "${RED}✗ %s${NC}\n" "$1"
}

# ============================================================================
# Main Script
# ============================================================================

print_header

# Step 1: Check if vault.yml exists
print_step "Step 1: Checking vault.yml..."
if [[ ! -f "$VAULT_FILE" ]]; then
    print_error "vault.yml not found at $VAULT_FILE"
    exit 1
fi
print_success "vault.yml found"

# Step 2: Check if vault.yml is encrypted
print_step "Step 2: Checking if vault.yml is encrypted..."
if grep -q "^\$ANSIBLE_VAULT" "$VAULT_FILE"; then
    print_warning "vault.yml is already encrypted"
    printf "   To edit: ${CYAN}make vault-edit FILE=group_vars/all/vault.yml${NC}\n"
else
    print_success "vault.yml is not encrypted (plain text - ready for editing)"
fi

# Step 3: Find all encrypted files
print_step "Step 3: Finding all encrypted files in roles/..."
printf "\n"

encrypted_files=()
while IFS= read -r -d '' file; do
    if grep -q "^\$ANSIBLE_VAULT" "$file" 2>/dev/null; then
        encrypted_files+=("$file")
    fi
done < <(find "$PROJECT_ROOT/roles" -type f \( -name "*.yml" -o -name ".env" \) -print0 2>/dev/null)

if [[ ${#encrypted_files[@]} -eq 0 ]]; then
    print_success "No encrypted files found in roles/ directory"
    print_success "Migration not needed or already completed!"
    exit 0
fi

printf "${YELLOW}Found ${#encrypted_files[@]} encrypted files:${NC}\n\n"
for file in "${encrypted_files[@]}"; do
    rel_path="${file#$PROJECT_ROOT/}"
    printf "  ${CYAN}•${NC} %s\n" "$rel_path"
done
printf "\n"

# Step 4: Create backup
print_step "Step 4: Creating backup..."
mkdir -p "$BACKUP_DIR"

for file in "${encrypted_files[@]}"; do
    rel_path="${file#$PROJECT_ROOT/}"
    backup_file="$BACKUP_DIR/$rel_path"
    mkdir -p "$(dirname "$backup_file")"
    cp "$file" "$backup_file"
done

print_success "Backup created at: $BACKUP_DIR"

# Step 5: Provide migration instructions
printf "\n"
printf "${CYAN}═══════════════════════════════════════════════════════${NC}\n"
printf "${YELLOW}  Migration Instructions${NC}\n"
printf "${CYAN}═══════════════════════════════════════════════════════${NC}\n\n"

printf "${YELLOW}Manual Migration Steps:${NC}\n\n"

printf "${CYAN}1. Decrypt old files:${NC}\n"
printf "   ${GREEN}# View encrypted file content${NC}\n"
for file in "${encrypted_files[@]}"; do
    rel_path="${file#$PROJECT_ROOT/}"
    printf "   ansible-vault view %s\n" "$rel_path"
done
printf "\n"

printf "${CYAN}2. Copy credentials to vault.yml:${NC}\n"
printf "   ${GREEN}# Edit centralized vault${NC}\n"
printf "   make vault-edit FILE=group_vars/all/vault.yml\n"
printf "   ${GREEN}# Copy credentials dari old files ke appropriate sections${NC}\n\n"

printf "${CYAN}3. Update tasks to use new variables:${NC}\n"
printf "   ${GREEN}# Example: roles/mysql-setup/tasks/main.yml${NC}\n"
printf "   ${YELLOW}# Old:${NC}\n"
printf "   environment:\n"
printf "     MYSQL_ROOT_PASSWORD: \"{{ mysql_root_password }}\"\n"
printf "   ${GREEN}# New:${NC}\n"
printf "   environment:\n"
printf "     MYSQL_ROOT_PASSWORD: \"{{ vault_mysql_root_password }}\"\n\n"

printf "${CYAN}4. Test deployment:${NC}\n"
printf "   make ping\n"
printf "   make setup-dry-run\n\n"

printf "${CYAN}5. Remove old encrypted files (after testing):${NC}\n"
printf "   ${YELLOW}# Backup is at: $BACKUP_DIR${NC}\n"
for file in "${encrypted_files[@]}"; do
    rel_path="${file#$PROJECT_ROOT/}"
    printf "   rm %s\n" "$rel_path"
done
printf "\n"

printf "${CYAN}═══════════════════════════════════════════════════════${NC}\n\n"

printf "${GREEN}Quick Reference:${NC}\n"
printf "  View vault:   ${CYAN}make vault-view FILE=group_vars/all/vault.yml${NC}\n"
printf "  Edit vault:   ${CYAN}make vault-edit FILE=group_vars/all/vault.yml${NC}\n"
printf "  Encrypt:      ${CYAN}make vault-encrypt FILE=group_vars/all/vault.yml${NC}\n"
printf "  Test:         ${CYAN}make setup-dry-run${NC}\n"
printf "\n"

printf "${GREEN}Documentation:${NC}\n"
printf "  Vault Guide:  ${CYAN}cat group_vars/README.md${NC}\n"
printf "  Main README:  ${CYAN}cat README.md${NC}\n"
printf "\n"

print_success "Migration information gathered successfully!"
printf "\n"
