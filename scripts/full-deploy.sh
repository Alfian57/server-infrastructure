#!/bin/bash
# =============================================================================
# Full Deployment Script
# =============================================================================
# Script untuk menjalankan full deployment dalam 1 command
# Usage: ./scripts/full-deploy.sh [options]
#
# Options:
#   --dry-run     : Jalankan dalam mode dry-run (tidak ada perubahan)
#   --verbose     : Mode verbose (-vvv)
#   --skip-apt    : Skip apt update
#   --apps-only   : Deploy aplikasi saja
#   --app NAME    : Deploy satu aplikasi dari catalog
#   --fresh       : Run seeders on fresh deployments (non-destructive)
#   --help        : Tampilkan bantuan
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PLAYBOOK="$PROJECT_DIR/playbooks/server-setup.yml"
INVENTORY="$PROJECT_DIR/inventory/hosts.ini"
VAULT_PASS="$PROJECT_DIR/.vault_pass"

# Default options
DRY_RUN=""
VERBOSE=""
SKIP_TAGS=""
EXTRA_VARS=""
LIMIT_TAGS=""
APP_FILTER=""
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-$PROJECT_DIR/.ansible/tmp}"

# Functions
print_header() {
    echo -e "${BLUE}"
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  🚀 Server Infrastructure Deployment"
    echo "═══════════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

print_step() {
    echo -e "${GREEN}▶ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --dry-run     Jalankan dalam mode dry-run (tidak ada perubahan)"
    echo "  --verbose     Mode verbose (-vvv)"
    echo "  --skip-apt    Skip apt update"
    echo "  --apps-only   Deploy aplikasi saja"
    echo "  --app NAME    Deploy satu aplikasi dari catalog"
    echo "  --infra-only  Deploy infrastructure saja"
    echo "  --db-only     Deploy databases saja"
    echo "  --fresh       Run seeders on fresh deployments (non-destructive)"
    echo "  --help        Tampilkan bantuan ini"
    echo ""
    echo "Examples:"
    echo "  $0                    # Full deployment"
    echo "  $0 --dry-run          # Preview perubahan"
    echo "  $0 --apps-only        # Deploy aplikasi saja"
    echo "  $0 --fresh            # Run seeders for fresh app deployments"
    exit 0
}

check_requirements() {
    print_step "Checking requirements..."
    
    # Check ansible
    if ! command -v ansible-playbook &> /dev/null; then
        print_error "ansible-playbook not found. Install with: pip install ansible"
        exit 1
    fi
    
    # Check vault password
    if [ ! -f "$VAULT_PASS" ]; then
        print_warning "Vault password file not found. You will be prompted for password."
        VAULT_OPTS="--ask-vault-pass"
    else
        VAULT_OPTS="--vault-password-file=$VAULT_PASS"
    fi
    
    # Check inventory
    if [ ! -f "$INVENTORY" ]; then
        print_error "Inventory file not found: $INVENTORY"
        exit 1
    fi
    
    # Check playbook
    if [ ! -f "$PLAYBOOK" ]; then
        print_error "Playbook not found: $PLAYBOOK"
        exit 1
    fi
    
    print_success "All requirements met"
}

test_connection() {
    print_step "Testing server connection..."
    
    if ansible all -i "$INVENTORY" $VAULT_OPTS -m ping -o &> /dev/null; then
        print_success "Server is reachable"
    else
        print_error "Cannot connect to server. Please check:"
        echo "  - Is the server running?"
        echo "  - Is SSH accessible?"
        echo "  - Is the SSH key correct?"
        echo ""
        echo "If this is a fresh server, run: make bootstrap"
        exit 1
    fi
}

syntax_check() {
    print_step "Checking playbook syntax..."
    
    if ansible-playbook "$PLAYBOOK" -i "$INVENTORY" $VAULT_OPTS --syntax-check &> /dev/null; then
        print_success "Syntax check passed"
    else
        print_error "Syntax check failed"
        ansible-playbook "$PLAYBOOK" -i "$INVENTORY" $VAULT_OPTS --syntax-check
        exit 1
    fi
}

run_deployment() {
    print_step "Starting deployment..."
    echo ""
    
    # Build command without eval so paths and vars are passed safely.
    CMD=(ansible-playbook "$PLAYBOOK" -i "$INVENTORY")

    if [ "$VAULT_OPTS" = "--ask-vault-pass" ]; then
        CMD+=(--ask-vault-pass)
    elif [ -n "$VAULT_OPTS" ]; then
        CMD+=("$VAULT_OPTS")
    fi
    
    # Add options
    [ -n "$DRY_RUN" ] && CMD+=(--check --diff)
    [ -n "$VERBOSE" ] && CMD+=(-vvv)
    [ -n "$SKIP_TAGS" ] && CMD+=(--skip-tags "$SKIP_TAGS")
    [ -n "$LIMIT_TAGS" ] && CMD+=(--tags "$LIMIT_TAGS")
    [ -n "$EXTRA_VARS" ] && CMD+=(-e "$EXTRA_VARS")
    if [ -n "$APP_FILTER" ]; then
        APP_TAG_ARGS=(deploy-tags --app "$APP_FILTER")
        if [ -z "$DRY_RUN" ]; then
            APP_TAG_ARGS+=(--include-runtime-deps)
        fi
        APP_TAGS=$("$PROJECT_DIR/scripts/app-catalog.py" "${APP_TAG_ARGS[@]}")
        CMD+=(--tags "$APP_TAGS" -e "app=$APP_FILTER")
    fi
    
    # Run
    printf "Command:"
    printf " %q" "${CMD[@]}"
    echo ""
    echo ""
    "${CMD[@]}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --verbose)
            VERBOSE="true"
            shift
            ;;
        --skip-apt)
            SKIP_TAGS="update-apt"
            shift
            ;;
        --apps-only)
            LIMIT_TAGS="application"
            shift
            ;;
        --app)
            APP_FILTER="$2"
            shift 2
            ;;
        --infra-only)
            LIMIT_TAGS="infrastructure"
            shift
            ;;
        --db-only)
            LIMIT_TAGS="database"
            shift
            ;;
        --fresh)
            EXTRA_VARS="run_seeder_on_deploy=true confirm_destroy_data=yes"
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main
print_header

echo "Configuration:"
echo "  Playbook:  $PLAYBOOK"
echo "  Inventory: $INVENTORY"
[ -n "$DRY_RUN" ] && echo "  Mode:      DRY-RUN (no changes)"
[ -n "$VERBOSE" ] && echo "  Verbose:   enabled"
[ -n "$SKIP_TAGS" ] && echo "  Skip:      $SKIP_TAGS"
[ -n "$LIMIT_TAGS" ] && echo "  Tags:      $LIMIT_TAGS"
[ -n "$APP_FILTER" ] && echo "  App:       $APP_FILTER"
[ -n "$EXTRA_VARS" ] && echo "  Extra:     $EXTRA_VARS"
echo ""

check_requirements
test_connection
syntax_check
run_deployment

echo ""
print_success "Deployment completed!"
echo -e "${BLUE}"
echo "═══════════════════════════════════════════════════════════════════"
echo "  Deployment Summary"
echo "═══════════════════════════════════════════════════════════════════"
echo -e "${NC}"
echo "Next steps:"
echo "  1. Verify services:  make status"
echo "  2. Check containers: make containers"
echo "  3. View logs:        make logs CONTAINER=<name>"
echo ""
