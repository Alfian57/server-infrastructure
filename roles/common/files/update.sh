#!/bin/bash

# Stricter error handling
set -euo pipefail

# Configuration
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
COMPOSE_PROJECT_NAME=$(basename "$PWD")
PASSWORD_FILE="${DOCKER_PASSWORD_FILE:-/opt/docker-stack/docker-password.txt}"
REGISTRY="${DOCKER_REGISTRY:-ghcr.io}"
REGISTRY_USER="${DOCKER_REGISTRY_USER:-alfian57}"
LOG_FILE="/var/log/docker-updates/${COMPOSE_PROJECT_NAME}.log"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp
    local log_dir
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    log_dir=$(dirname "${LOG_FILE}")
    
    # Print to stdout
    echo "[${timestamp}] [${level}] ${message}"
    
    # Append only when the target file is writable, or when it can be created.
    if { [[ -e "${LOG_FILE}" ]] && [[ -w "${LOG_FILE}" ]]; } || { [[ ! -e "${LOG_FILE}" ]] && [[ -w "${log_dir}" ]]; }; then
        echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}" 2>/dev/null || true
    fi
}

# Error handler
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Create log directory if it doesn't exist (try with sudo if needed)
if [[ ! -d "$(dirname "${LOG_FILE}")" ]]; then
    mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || \
    sudo mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || \
    log "WARN" "Could not create log directory, logging to stdout only"
fi

# Make log directory writable if possible
if [[ -d "$(dirname "${LOG_FILE}")" ]] && [[ ! -w "$(dirname "${LOG_FILE}")" ]]; then
    sudo chown -R "$(whoami):$(whoami)" "$(dirname "${LOG_FILE}")" 2>/dev/null || \
    log "WARN" "Could not set log directory permissions"
fi

if [[ -e "${LOG_FILE}" ]] && [[ ! -w "${LOG_FILE}" ]]; then
    sudo chown "$(whoami):$(whoami)" "${LOG_FILE}" 2>/dev/null || true
fi

log "INFO" "Starting update for ${COMPOSE_PROJECT_NAME}"

# Validate compose file exists
[[ -f "${COMPOSE_FILE}" ]] || error_exit "Docker compose file not found: ${COMPOSE_FILE}"

# Validate password file exists
[[ -f "${PASSWORD_FILE}" ]] || error_exit "Password file not found: ${PASSWORD_FILE}"

COMPOSE_IMAGES=$(docker compose -f "${COMPOSE_FILE}" config | awk '/^[[:space:]]+image:/ {print $2}' | sort | uniq)
declare -A OLD_IMAGE_IDS=()

log "INFO" "Recording currently deployed image IDs"
for IMAGE in ${COMPOSE_IMAGES}; do
    IMAGE_ID=$(docker image inspect "${IMAGE}" --format '{{.Id}}' 2>/dev/null || true)
    if [[ -n "${IMAGE_ID}" ]]; then
        OLD_IMAGE_IDS["${IMAGE}"]="${IMAGE_ID}"
        log "INFO" "Current image for ${IMAGE}: ${IMAGE_ID}"
    else
        log "INFO" "No existing local image found for ${IMAGE}"
    fi
done

# Login to registry (try with sudo if password file is not readable)
log "INFO" "Logging in to ${REGISTRY}"
LOGIN_SUCCESS=false

# Try direct read first
if [[ -r "${PASSWORD_FILE}" ]]; then
    if docker login "${REGISTRY}" --username "${REGISTRY_USER}" --password-stdin < "${PASSWORD_FILE}" > /dev/null 2>&1; then
        LOGIN_SUCCESS=true
    fi
fi

# Try with sudo if direct read failed
if [[ "${LOGIN_SUCCESS}" != "true" ]]; then
    if sudo cat "${PASSWORD_FILE}" 2>/dev/null | docker login "${REGISTRY}" --username "${REGISTRY_USER}" --password-stdin > /dev/null 2>&1; then
        LOGIN_SUCCESS=true
    fi
fi

if [[ "${LOGIN_SUCCESS}" == "true" ]]; then
    log "INFO" "Successfully logged in to ${REGISTRY}"
else
    error_exit "Failed to login to ${REGISTRY}"
fi

# Pull latest images
log "INFO" "Pulling latest images"
if docker compose -f "${COMPOSE_FILE}" pull; then
    log "INFO" "Successfully pulled latest images"
else
    error_exit "Failed to pull images"
fi

# Deploy containers with new images (rolling update - no down first)
log "INFO" "Deploying containers with rolling update"
if docker compose -f "${COMPOSE_FILE}" up -d --pull always --force-recreate --remove-orphans; then
    log "INFO" "Successfully deployed containers"
else
    error_exit "Failed to deploy containers"
fi

run_laravel_post_deploy() {
    local service=$1

    log "INFO" "Detected Laravel application in service ${service}"
    log "INFO" "Clearing Laravel runtime caches"
    docker compose -f "${COMPOSE_FILE}" exec -T "${service}" php artisan optimize:clear || \
        error_exit "Failed to clear Laravel caches for ${service}"

    log "INFO" "Running Laravel migrations"
    docker compose -f "${COMPOSE_FILE}" exec -T "${service}" php artisan migrate --force || \
        error_exit "Failed to run Laravel migrations for ${service}"

    log "INFO" "Rebuilding Laravel runtime caches"
    docker compose -f "${COMPOSE_FILE}" exec -T "${service}" php artisan config:cache || \
        error_exit "Failed to cache Laravel config for ${service}"
    docker compose -f "${COMPOSE_FILE}" exec -T "${service}" php artisan route:cache || \
        log "WARN" "Could not cache Laravel routes for ${service}"
    docker compose -f "${COMPOSE_FILE}" exec -T "${service}" php artisan view:cache || \
        log "WARN" "Could not cache Laravel views for ${service}"

    log "INFO" "Restarting Laravel workers"
    docker compose -f "${COMPOSE_FILE}" exec -T "${service}" php artisan queue:restart || \
        log "WARN" "Could not restart Laravel queue workers for ${service}"

    # Some images disable opcache timestamp validation, so restart after cache rebuild.
    log "INFO" "Restarting ${service} to load fresh Laravel config"
    docker compose -f "${COMPOSE_FILE}" restart "${service}" || \
        error_exit "Failed to restart Laravel service ${service}"
}

run_prisma_post_deploy() {
    local service=$1

    log "INFO" "Detected Prisma application in service ${service}"
    log "INFO" "Running Prisma migrations"
    docker compose -f "${COMPOSE_FILE}" exec -T "${service}" npx prisma migrate deploy || \
        error_exit "Failed to run Prisma migrations for ${service}"
}

log "INFO" "Checking for Laravel post-deploy tasks"
SERVICES=$(docker compose -f "${COMPOSE_FILE}" ps --services --filter status=running)
for SERVICE in ${SERVICES}; do
    if docker compose -f "${COMPOSE_FILE}" exec -T "${SERVICE}" sh -lc 'test -f artisan' > /dev/null 2>&1; then
        run_laravel_post_deploy "${SERVICE}"
    fi
    if docker compose -f "${COMPOSE_FILE}" exec -T "${SERVICE}" sh -lc 'test -f prisma/schema.prisma && command -v npx' > /dev/null 2>&1; then
        run_prisma_post_deploy "${SERVICE}"
    fi
done

# Logout from registry
log "INFO" "Logging out from ${REGISTRY}"
docker logout "${REGISTRY}" > /dev/null 2>&1 || log "WARN" "Logout failed, but continuing"

# Cleanup old images
log "INFO" "Starting image cleanup"

RUNNING_CONTAINER_IMAGE_IDS=$(docker ps -aq | xargs -r docker inspect --format '{{.Image}}' | sort | uniq)

REMOVED_COUNT=0
for IMAGE in ${COMPOSE_IMAGES}; do
    OLD_IMAGE_ID="${OLD_IMAGE_IDS[${IMAGE}]:-}"
    NEW_IMAGE_ID=$(docker image inspect "${IMAGE}" --format '{{.Id}}' 2>/dev/null || true)

    if [[ -z "${OLD_IMAGE_ID}" ]]; then
        log "INFO" "Skipping cleanup for ${IMAGE}: no previous image ID recorded"
        continue
    fi

    if [[ "${OLD_IMAGE_ID}" == "${NEW_IMAGE_ID}" ]]; then
        log "INFO" "Skipping cleanup for ${IMAGE}: image ID did not change"
        continue
    fi

    if echo "${RUNNING_CONTAINER_IMAGE_IDS}" | grep -qF "${OLD_IMAGE_ID}"; then
        log "INFO" "Skipping old image for ${IMAGE}: still used by a container (${OLD_IMAGE_ID})"
        continue
    fi

    if docker rmi "${OLD_IMAGE_ID}" > /dev/null 2>&1; then
        log "INFO" "Removed old image for ${IMAGE}: ${OLD_IMAGE_ID}"
        ((REMOVED_COUNT+=1))
    else
        log "WARN" "Could not remove old image for ${IMAGE}: ${OLD_IMAGE_ID}"
    fi
done

log "INFO" "Cleanup complete. Removed ${REMOVED_COUNT} unused images"
log "INFO" "Update completed successfully for ${COMPOSE_PROJECT_NAME}"

exit 0
