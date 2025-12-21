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
    
    # Print to stdout
    echo "[${timestamp}] [${level}] ${message}"
    
    # Try to log to file if directory is writable
    if [[ -w "$(dirname "${LOG_FILE}")" ]] || [[ -w "${LOG_FILE}" ]]; then
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
    sudo chown -R $(whoami):$(whoami) "$(dirname "${LOG_FILE}")" 2>/dev/null || \
    log "WARN" "Could not set log directory permissions"
fi

log "INFO" "Starting update for ${COMPOSE_PROJECT_NAME}"

# Validate compose file exists
[[ -f "${COMPOSE_FILE}" ]] || error_exit "Docker compose file not found: ${COMPOSE_FILE}"

# Validate password file exists
[[ -f "${PASSWORD_FILE}" ]] || error_exit "Password file not found: ${PASSWORD_FILE}"

# Login to registry (try with sudo if password file is not readable)
log "INFO" "Logging in to ${REGISTRY}"
LOGIN_SUCCESS=false

# Try direct read first
if [[ -r "${PASSWORD_FILE}" ]]; then
    if cat "${PASSWORD_FILE}" | docker login "${REGISTRY}" --username "${REGISTRY_USER}" --password-stdin > /dev/null 2>&1; then
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

# Deploy containers with new images
log "INFO" "Deploying containers"

# Stop existing containers first to avoid "container is running" error
log "INFO" "Stopping existing containers..."
docker compose -f "${COMPOSE_FILE}" down --remove-orphans 2>/dev/null || true

# Start containers with new images
if docker compose -f "${COMPOSE_FILE}" up -d --force-recreate; then
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
