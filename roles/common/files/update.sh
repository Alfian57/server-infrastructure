#!/bin/bash

# Stricter error handling
set -euo pipefail

# Configuration
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
COMPOSE_PROJECT_NAME=$(basename "$PWD")
PASSWORD_FILE="${DOCKER_PASSWORD_FILE:-/opt/docker-stack/docker-password.txt}"
REGISTRY="${DOCKER_REGISTRY:-ghcr.io}"
REGISTRY_USER="${DOCKER_REGISTRY_USER:-alfiangadingsaputra@gmail.com}"
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
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Error handler
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Create log directory if it doesn't exist
mkdir -p "$(dirname "${LOG_FILE}")"

log "INFO" "Starting update for ${COMPOSE_PROJECT_NAME}"

# Validate compose file exists
[[ -f "${COMPOSE_FILE}" ]] || error_exit "Docker compose file not found: ${COMPOSE_FILE}"

# Validate password file exists
[[ -f "${PASSWORD_FILE}" ]] || error_exit "Password file not found: ${PASSWORD_FILE}"

# Login to registry
log "INFO" "Logging in to ${REGISTRY}"
if cat "${PASSWORD_FILE}" | docker login "${REGISTRY}" --username "${REGISTRY_USER}" --password-stdin > /dev/null 2>&1; then
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

# Deploy containers with new images
log "INFO" "Deploying containers"
if docker compose -f "${COMPOSE_FILE}" up -d; then
    log "INFO" "Successfully deployed containers"
else
    error_exit "Failed to deploy containers"
fi

# Logout from registry
log "INFO" "Logging out from ${REGISTRY}"
docker logout "${REGISTRY}" > /dev/null 2>&1 || log "WARN" "Logout failed, but continuing"

# Cleanup old images
log "INFO" "Starting image cleanup"

# Get images defined in this compose file
USED_IMAGES=$(docker compose -f "${COMPOSE_FILE}" config | grep 'image:' | awk '{print $2}' | sort | uniq)

# Get all images currently in use by any container
ALL_USED_IMAGES=$(docker ps -a --format '{{.Image}}' | sort | uniq)

# Remove unused images from this compose
REMOVED_COUNT=0
for IMAGE in ${USED_IMAGES}; do
    # Skip if image is currently in use
    if echo "${ALL_USED_IMAGES}" | grep -qF "${IMAGE}"; then
        log "INFO" "Skipping in-use image: ${IMAGE}"
        continue
    fi
    
    # Try to remove unused image
    if docker rmi "${IMAGE}" 2>/dev/null; then
        log "INFO" "Removed unused image: ${IMAGE}"
        ((REMOVED_COUNT++))
    else
        log "WARN" "Could not remove image: ${IMAGE}"
    fi
done

log "INFO" "Cleanup complete. Removed ${REMOVED_COUNT} unused images"
log "INFO" "Update completed successfully for ${COMPOSE_PROJECT_NAME}"

exit 0
