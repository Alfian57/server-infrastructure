#!/bin/bash
# =============================================================================
# Artisan Commands Helper Script for Laravel Applications
# =============================================================================
# This script provides quick access to common artisan commands for debugging
# and emergency scenarios.
#
# Usage:
#   ./artisan-commands.sh migrate           # Run migrations
#   ./artisan-commands.sh fresh             # Run migrate:fresh (WARNING: destroys data)
#   ./artisan-commands.sh seed              # Run seeders
#   ./artisan-commands.sh all               # Run migrate:fresh + seed
#   ./artisan-commands.sh status            # Show migration status
#   ./artisan-commands.sh cache-clear       # Clear all caches
#   ./artisan-commands.sh optimize          # Optimize application
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Get container name from directory name or argument
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME=$(basename "$SCRIPT_DIR")

print_header() {
  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║${NC}  ${GREEN}Artisan Commands - ${APP_NAME}${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

print_warning() {
  echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

run_artisan() {
  echo -e "${BLUE}▶ Running: php artisan $*${NC}"
  docker exec "$APP_NAME" php artisan "$@"
}

COMMAND="${1:-}"

if [[ -n "$COMMAND" && "$COMMAND" != "help" && "$COMMAND" != "--help" ]] && ! docker container inspect "$APP_NAME" >/dev/null 2>&1; then
  print_error "Container not found: $APP_NAME"
  exit 1
fi

case "$COMMAND" in
  migrate)
    print_header
    run_artisan migrate --force
    print_success "Migrations completed"
    ;;
  fresh)
    print_header
    print_warning "This will DESTROY all data in the database!"
    read -p "Are you sure? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      run_artisan migrate:fresh --force
      print_success "Database reset completed"
    else
      echo "Cancelled."
    fi
    ;;
  seed)
    print_header
    run_artisan db:seed --force
    print_success "Seeding completed"
    ;;
  all)
    print_header
    print_warning "This will DESTROY all data and reseed the database!"
    read -p "Are you sure? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      run_artisan migrate:fresh --force --seed
      print_success "Database reset and seeded"
    else
      echo "Cancelled."
    fi
    ;;
  status)
    print_header
    run_artisan migrate:status
    ;;
  cache-clear)
    print_header
    run_artisan config:clear
    run_artisan route:clear
    run_artisan view:clear
    run_artisan cache:clear
    print_success "All caches cleared"
    ;;
  optimize)
    print_header
    run_artisan config:cache
    run_artisan route:cache
    run_artisan view:cache
    print_success "Application optimized"
    ;;
  help|--help)
    print_header
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  migrate      Run database migrations"
    echo "  fresh        Run migrate:fresh (WARNING: destroys data)"
    echo "  seed         Run database seeders"
    echo "  all          Run migrate:fresh + seed"
    echo "  status       Show migration status"
    echo "  cache-clear  Clear all caches"
    echo "  optimize     Optimize application (cache config/routes/views)"
    echo ""
    exit 0
    ;;
  "")
    print_header
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  migrate      Run database migrations"
    echo "  fresh        Run migrate:fresh (WARNING: destroys data)"
    echo "  seed         Run database seeders"
    echo "  all          Run migrate:fresh + seed"
    echo "  status       Show migration status"
    echo "  cache-clear  Clear all caches"
    echo "  optimize     Optimize application (cache config/routes/views)"
    echo ""
    exit 1
    ;;
  *)
    print_error "Unknown command: $COMMAND"
    echo "Run: $0 --help"
    exit 1
    ;;
esac
