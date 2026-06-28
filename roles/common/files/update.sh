#!/bin/bash
# =============================================================================
# Zero-touch container update & deploy helper
# =============================================================================
# Executed on the server by each application's CI/CD pipeline (via SSH) and can
# also be run manually. It performs a safe rolling update:
#
#   1. Acquire a per-project lock (prevents overlapping deploys).
#   2. Log in to the container registry.
#   3. Record currently deployed image IDs (for later cleanup).
#   4. Pull the latest images and recreate containers.
#   5. Wait for the app containers to become ready (healthy/running).
#   6. Run NEW database migrations for the detected stack:
#        - Laravel : php artisan migrate --force
#        - Prisma  : npx prisma migrate deploy
#        - Golang  : ./migrate up        (project convention)
#      Migrations are idempotent: only pending migrations are applied.
#      Seeders are intentionally NOT run here (they can be destructive and
#      must stay an explicit, opt-in action handled by Ansible).
#   7. Clean up images that were replaced by this deploy, plus dangling images.
#
# Configuration (override via environment variables):
#   COMPOSE_FILE          docker compose file            (default: docker-compose.yml)
#   DOCKER_PASSWORD_FILE  registry password file         (default: /opt/docker-stack/docker-password.txt)
#   DOCKER_REGISTRY       registry host                  (default: ghcr.io)
#   DOCKER_REGISTRY_USER  registry username              (default: alfian57)
#   MIGRATE_ON_DEPLOY     run migrations after deploy    (default: true)
#   READINESS_TIMEOUT     seconds to wait for readiness  (default: 180)
#   PRUNE_DANGLING        prune dangling images at end   (default: true)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
COMPOSE_PROJECT_NAME="$(basename "$PWD")"
PASSWORD_FILE="${DOCKER_PASSWORD_FILE:-/opt/docker-stack/docker-password.txt}"
REGISTRY="${DOCKER_REGISTRY:-ghcr.io}"
REGISTRY_USER="${DOCKER_REGISTRY_USER:-alfian57}"
LOG_FILE="/var/log/docker-updates/${COMPOSE_PROJECT_NAME}.log"
LOCK_FILE="/tmp/docker-update-${COMPOSE_PROJECT_NAME}.lock"

MIGRATE_ON_DEPLOY="${MIGRATE_ON_DEPLOY:-true}"
READINESS_TIMEOUT="${READINESS_TIMEOUT:-180}"
PRUNE_DANGLING="${PRUNE_DANGLING:-true}"

REGISTRY_LOGGED_IN=false

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp log_dir
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    log_dir=$(dirname "${LOG_FILE}")

    echo "[${timestamp}] [${level}] ${message}"

    # Append to the log file only when it is writable (or creatable).
    if { [[ -e "${LOG_FILE}" ]] && [[ -w "${LOG_FILE}" ]]; } || { [[ ! -e "${LOG_FILE}" ]] && [[ -w "${log_dir}" ]]; }; then
        echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}" 2>/dev/null || true
    fi
}

compose() {
    docker compose -f "${COMPOSE_FILE}" "$@"
}

# ---------------------------------------------------------------------------
# Cleanup trap: always log out of the registry and release the lock
# ---------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    if [[ "${REGISTRY_LOGGED_IN}" == "true" ]]; then
        docker logout "${REGISTRY}" > /dev/null 2>&1 || true
    fi
    return "${exit_code}"
}
trap cleanup EXIT

error_exit() {
    log "ERROR" "$1"
    exit 1
}

# ---------------------------------------------------------------------------
# Prepare log directory / file (best effort, tolerate non-root execution)
# ---------------------------------------------------------------------------
prepare_log_target() {
    local log_dir
    log_dir=$(dirname "${LOG_FILE}")

    if [[ ! -d "${log_dir}" ]]; then
        mkdir -p "${log_dir}" 2>/dev/null \
            || sudo mkdir -p "${log_dir}" 2>/dev/null \
            || log "WARN" "Could not create log directory, logging to stdout only"
    fi

    if [[ -d "${log_dir}" ]] && [[ ! -w "${log_dir}" ]]; then
        sudo chown -R "$(whoami):$(whoami)" "${log_dir}" 2>/dev/null \
            || log "WARN" "Could not set log directory permissions"
    fi

    if [[ -e "${LOG_FILE}" ]] && [[ ! -w "${LOG_FILE}" ]]; then
        sudo chown "$(whoami):$(whoami)" "${LOG_FILE}" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Concurrency lock: avoid two deploys racing on the same project
# ---------------------------------------------------------------------------
acquire_lock() {
    exec 9>"${LOCK_FILE}" 2>/dev/null || return 0
    if ! flock -n 9; then
        error_exit "Another update for ${COMPOSE_PROJECT_NAME} is already running (lock: ${LOCK_FILE})"
    fi
}

# ---------------------------------------------------------------------------
# Registry login (direct read, then sudo fallback)
# ---------------------------------------------------------------------------
registry_login() {
    log "INFO" "Logging in to ${REGISTRY}"
    if [[ -r "${PASSWORD_FILE}" ]] \
        && docker login "${REGISTRY}" --username "${REGISTRY_USER}" --password-stdin < "${PASSWORD_FILE}" > /dev/null 2>&1; then
        REGISTRY_LOGGED_IN=true
    elif sudo cat "${PASSWORD_FILE}" 2>/dev/null | docker login "${REGISTRY}" --username "${REGISTRY_USER}" --password-stdin > /dev/null 2>&1; then
        REGISTRY_LOGGED_IN=true
    fi

    if [[ "${REGISTRY_LOGGED_IN}" == "true" ]]; then
        log "INFO" "Successfully logged in to ${REGISTRY}"
    else
        error_exit "Failed to login to ${REGISTRY}"
    fi
}

# ---------------------------------------------------------------------------
# Record the image IDs that are deployed BEFORE the update, so we can remove
# the exact images this deploy replaces (and nothing that is still in use).
# ---------------------------------------------------------------------------
declare -A OLD_IMAGE_IDS=()
COMPOSE_IMAGES=""

record_old_image_ids() {
    COMPOSE_IMAGES=$(compose config 2>/dev/null | awk '/^[[:space:]]+image:/ {print $2}' | sort -u)
    log "INFO" "Recording currently deployed image IDs"
    local image image_id
    for image in ${COMPOSE_IMAGES}; do
        image_id=$(docker image inspect "${image}" --format '{{.Id}}' 2>/dev/null || true)
        if [[ -n "${image_id}" ]]; then
            OLD_IMAGE_IDS["${image}"]="${image_id}"
            log "INFO" "Current image for ${image}: ${image_id}"
        else
            log "INFO" "No existing local image found for ${image}"
        fi
    done
}

# ---------------------------------------------------------------------------
# Pull latest images and recreate containers (rolling update)
# ---------------------------------------------------------------------------
deploy() {
    log "INFO" "Pulling latest images"
    compose pull || error_exit "Failed to pull images"

    # Images are already pulled above; --pull never avoids a second registry
    # round-trip during `up` (some SSH/CI sessions do not reuse credentials there).
    log "INFO" "Recreating containers (rolling update)"
    compose up -d --pull never --remove-orphans || error_exit "Failed to deploy containers"
    log "INFO" "Containers deployed"
}

# ---------------------------------------------------------------------------
# Wait until each running service is ready:
#   - if it has a healthcheck  -> wait for 'healthy'
#   - otherwise                -> wait for 'running'
# Non-fatal: logs a warning and continues if the timeout is reached, so that
# migration steps below still get a chance (and surface a clearer error).
# ---------------------------------------------------------------------------
wait_for_ready() {
    local deadline=$(( SECONDS + READINESS_TIMEOUT ))
    local services service cid state health
    services=$(compose ps --services 2>/dev/null || true)

    for service in ${services}; do
        cid=$(compose ps -q "${service}" 2>/dev/null | head -n1)
        [[ -z "${cid}" ]] && continue

        while true; do
            state=$(docker inspect -f '{{.State.Status}}' "${cid}" 2>/dev/null || echo "unknown")
            health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cid}" 2>/dev/null || echo "none")

            if [[ "${health}" == "healthy" ]] || { [[ "${health}" == "none" ]] && [[ "${state}" == "running" ]]; }; then
                log "INFO" "Service ${service} is ready (state=${state}, health=${health})"
                break
            fi

            if [[ "${state}" == "exited" || "${state}" == "dead" ]]; then
                log "WARN" "Service ${service} is ${state}; continuing (migrations may surface the cause)"
                break
            fi

            if (( SECONDS >= deadline )); then
                log "WARN" "Timed out waiting for ${service} to become ready (state=${state}, health=${health})"
                break
            fi
            sleep 3
        done
    done
}

# ---------------------------------------------------------------------------
# Per-stack migration helpers. All are idempotent: only NEW migrations run.
# ---------------------------------------------------------------------------
run_laravel_migrations() {
    local service=$1
    log "INFO" "[${service}] Laravel detected - running migrations"
    compose exec -T "${service}" php artisan migrate --force \
        || error_exit "[${service}] Laravel migration failed"

    # Ensure the public storage symlink exists so uploaded/seeded media is
    # reachable. Idempotent: --force recreates it if missing (e.g. when storage
    # is a fresh named volume on first deploy or after a container recreate).
    log "INFO" "[${service}] Ensuring public storage symlink"
    compose exec -T "${service}" php artisan storage:link --force \
        || log "WARN" "[${service}] Could not create storage symlink"

    log "INFO" "[${service}] Refreshing Laravel caches"
    compose exec -T "${service}" php artisan optimize:clear \
        || error_exit "[${service}] Failed to clear Laravel caches"
    compose exec -T "${service}" php artisan config:cache \
        || error_exit "[${service}] Failed to cache Laravel config"
    compose exec -T "${service}" php artisan route:cache \
        || log "WARN" "[${service}] Could not cache Laravel routes"
    compose exec -T "${service}" php artisan view:cache \
        || log "WARN" "[${service}] Could not cache Laravel views"
    compose exec -T "${service}" php artisan queue:restart \
        || log "WARN" "[${service}] Could not restart queue workers"

    # Some images disable opcache timestamp validation; restart to load fresh config.
    log "INFO" "[${service}] Restarting to load fresh Laravel config"
    compose restart "${service}" || error_exit "[${service}] Failed to restart Laravel service"
}

run_prisma_migrations() {
    local service=$1
    log "INFO" "[${service}] Prisma detected - running 'prisma migrate deploy'"
    compose exec -T "${service}" npx prisma migrate deploy \
        || error_exit "[${service}] Prisma migration failed"
}

run_golang_migrations() {
    local service=$1
    log "INFO" "[${service}] Golang migrate binary detected - running './migrate up'"
    local output status
    set +e
    output=$(compose exec -T "${service}" ./migrate up 2>&1)
    status=$?
    set -e
    [[ -n "${output}" ]] && printf '%s\n' "${output}"

    # Treat "no pending migrations" as success regardless of exit code.
    if [[ ${status} -ne 0 ]] \
        && ! grep -qiE 'no change|no migration|nothing to migrate|already.*up to date' <<< "${output}"; then
        error_exit "[${service}] Golang migration failed (exit ${status})"
    fi
    log "INFO" "[${service}] Golang migrations up to date"
}

# Detect stack per running service and run the matching migration.
run_migrations() {
    if [[ "${MIGRATE_ON_DEPLOY}" != "true" ]]; then
        log "INFO" "MIGRATE_ON_DEPLOY=${MIGRATE_ON_DEPLOY}; skipping migrations"
        return 0
    fi

    log "INFO" "Checking for pending migrations across services"
    local services service
    services=$(compose ps --services --filter status=running 2>/dev/null || true)

    for service in ${services}; do
        # Laravel: artisan in the working directory.
        if compose exec -T "${service}" sh -lc 'test -f artisan' > /dev/null 2>&1; then
            run_laravel_migrations "${service}"
            continue
        fi
        # Prisma: schema present and npx available.
        if compose exec -T "${service}" sh -lc 'test -f prisma/schema.prisma && command -v npx >/dev/null 2>&1' > /dev/null 2>&1; then
            run_prisma_migrations "${service}"
            continue
        fi
        # Golang (project convention): an executable ./migrate in the workdir.
        if compose exec -T "${service}" sh -lc 'test -x ./migrate' > /dev/null 2>&1; then
            run_golang_migrations "${service}"
            continue
        fi
    done
}

# ---------------------------------------------------------------------------
# Remove images replaced by this deploy, then prune dangling images.
# ---------------------------------------------------------------------------
cleanup_images() {
    log "INFO" "Cleaning up replaced images"
    local running_ids image old_id new_id removed=0
    running_ids=$(docker ps -aq | xargs -r docker inspect --format '{{.Image}}' 2>/dev/null | sort -u)

    for image in ${COMPOSE_IMAGES}; do
        old_id="${OLD_IMAGE_IDS[${image}]:-}"
        new_id=$(docker image inspect "${image}" --format '{{.Id}}' 2>/dev/null || true)

        [[ -z "${old_id}" ]] && continue                       # nothing was deployed before
        [[ "${old_id}" == "${new_id}" ]] && continue           # image unchanged
        if grep -qF "${old_id}" <<< "${running_ids}"; then     # still used by a container
            log "INFO" "Keeping ${old_id}: still in use"
            continue
        fi

        if docker rmi "${old_id}" > /dev/null 2>&1; then
            log "INFO" "Removed replaced image ${old_id} (${image})"
            (( removed += 1 ))
        else
            log "WARN" "Could not remove old image ${old_id} (${image})"
        fi
    done
    log "INFO" "Removed ${removed} replaced image(s)"

    if [[ "${PRUNE_DANGLING}" == "true" ]]; then
        log "INFO" "Pruning dangling images"
        docker image prune -f > /dev/null 2>&1 || log "WARN" "Dangling image prune failed"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    prepare_log_target
    acquire_lock
    log "INFO" "Starting update for ${COMPOSE_PROJECT_NAME}"

    [[ -f "${COMPOSE_FILE}" ]]  || error_exit "Docker compose file not found: ${COMPOSE_FILE}"
    [[ -f "${PASSWORD_FILE}" ]] || error_exit "Password file not found: ${PASSWORD_FILE}"

    registry_login
    record_old_image_ids
    deploy
    wait_for_ready
    run_migrations
    cleanup_images

    log "INFO" "Update completed successfully for ${COMPOSE_PROJECT_NAME}"
}

main "$@"
exit 0
