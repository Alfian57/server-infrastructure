#!/usr/bin/env bash
# Ansible owns configuration; CI changes only the selected image references.
set -euo pipefail
umask 027
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

group=${1:-all}
tag=${2:-}
case "$group" in all|web|ml|rollback) ;; *) echo 'Usage: update.sh {all|web|ml|rollback} [sha-<40 hex>]' >&2; exit 2 ;; esac
if [[ -n "$tag" ]] && { [[ ! "$tag" =~ ^sha-[0-9a-f]{40}$ ]] || [[ "$group" != web && "$group" != ml ]]; }; then
  echo 'A commit tag is accepted only for web or ml updates.' >&2
  exit 2
fi
for file in docker-compose.yml deployment.env images.env .env broker.env ml.env stream.conf; do
  [[ -r "$file" ]] || { echo "Missing $file; bootstrap guardian-lab with Ansible first." >&2; exit 1; }
done

# Both repositories and Ansible take the same lock before reading image state.
exec 9>/tmp/guardian-lab-deploy.lock
flock -w 600 9
# shellcheck disable=SC1091
source ./deployment.env

candidate=$(mktemp "$PWD/.images.XXXXXX")
chmod --reference=images.env "$candidate"
chgrp --reference=images.env "$candidate"
registry_config=$(mktemp -d)
export DOCKER_CONFIG="$registry_config"
finish() {
  local status=$?
  if [[ -f "$candidate" ]]; then
    if [[ "$status" -ne 0 ]]; then
      mv -f -- "$candidate" images.failed.env
      echo 'Deployment failed. Image state was not committed; inspect services before recovery.' >&2
    else
      rm -f -- "$candidate"
    fi
  fi
  rm -rf -- "$registry_config"
  return "$status"
}
trap finish EXIT

if [[ "$group" == rollback ]]; then
  [[ -r images.previous.env ]] || { echo 'No previous image state available.' >&2; exit 1; }
  cp -- images.previous.env "$candidate"
else
  # shellcheck disable=SC1091
  source ./images.env
  if [[ -n "$tag" && "$group" == web ]]; then
    GUARDIAN_WEB_IMAGE="${WEB_REPOSITORY}:${tag}"
    GUARDIAN_BROKER_IMAGE="${BROKER_REPOSITORY}:${tag}"
    GUARDIAN_BROWSER_IMAGE="${BROWSER_REPOSITORY}:${tag}"
    GUARDIAN_EGRESS_IMAGE="${EGRESS_REPOSITORY}:${tag}"
  elif [[ -n "$tag" && "$group" == ml ]]; then
    GUARDIAN_ML_IMAGE="${ML_REPOSITORY}:${tag}"
  fi
  printf '%s\n' \
    "GUARDIAN_WEB_IMAGE=$GUARDIAN_WEB_IMAGE" \
    "GUARDIAN_BROKER_IMAGE=$GUARDIAN_BROKER_IMAGE" \
    "GUARDIAN_BROWSER_IMAGE=$GUARDIAN_BROWSER_IMAGE" \
    "GUARDIAN_EGRESS_IMAGE=$GUARDIAN_EGRESS_IMAGE" \
    "GUARDIAN_ML_IMAGE=$GUARDIAN_ML_IMAGE" > "$candidate"
fi

compose() {
  docker compose --project-name guardian-lab --env-file "$candidate" -f docker-compose.yml "$@"
}
compose config --quiet

if [[ -r "$REGISTRY_PASSWORD_FILE" ]]; then
  docker login "$REGISTRY" --username "$REGISTRY_USER" --password-stdin < "$REGISTRY_PASSWORD_FILE" >/dev/null
else
  sudo -n cat "$REGISTRY_PASSWORD_FILE" | docker login "$REGISTRY" --username "$REGISTRY_USER" --password-stdin >/dev/null
fi

case "$group" in
  ml) services=(ml) ;;
  web) services=(sandbox-web-image sandbox-egress-image broker app stream) ;;
  all|rollback) services=(ml sandbox-web-image sandbox-egress-image broker app stream) ;;
esac
compose pull "${services[@]}"

# Resolve pulled commit tags (including bootstrap latest) to immutable digests.
# References outside the selected group remain exactly as previously deployed.
# shellcheck disable=SC1090
source "$candidate"
case "$group" in
  ml) image_keys=(GUARDIAN_ML_IMAGE) ;;
  web) image_keys=(GUARDIAN_WEB_IMAGE GUARDIAN_BROKER_IMAGE GUARDIAN_BROWSER_IMAGE GUARDIAN_EGRESS_IMAGE) ;;
  all|rollback) image_keys=(GUARDIAN_WEB_IMAGE GUARDIAN_BROKER_IMAGE GUARDIAN_BROWSER_IMAGE GUARDIAN_EGRESS_IMAGE GUARDIAN_ML_IMAGE) ;;
esac
for key in "${image_keys[@]}"; do
  image=${!key}
  repository=${image%%@*}
  repository=${repository%:*}
  digests=$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$image")
  pinned=''
  while IFS= read -r digest; do
    if [[ "$digest" == "$repository@sha256:"* ]]; then pinned=$digest; break; fi
  done <<< "$digests"
  [[ -n "$pinned" ]] || { echo "No registry digest found for $key." >&2; exit 1; }
  printf -v "$key" '%s' "$pinned"
done
printf '%s\n' \
  "GUARDIAN_WEB_IMAGE=$GUARDIAN_WEB_IMAGE" \
  "GUARDIAN_BROKER_IMAGE=$GUARDIAN_BROKER_IMAGE" \
  "GUARDIAN_BROWSER_IMAGE=$GUARDIAN_BROWSER_IMAGE" \
  "GUARDIAN_EGRESS_IMAGE=$GUARDIAN_EGRESS_IMAGE" \
  "GUARDIAN_ML_IMAGE=$GUARDIAN_ML_IMAGE" > "$candidate"

if [[ "$group" != ml ]]; then
  # Start only inert image keepers; neither launches a browser nor Squid.
  compose up -d --no-deps --pull never sandbox-web-image sandbox-egress-image
  if [[ "$group" != rollback ]]; then
    # One-off process, using the same image as the web deployment; no demo users.
    compose run --rm --no-deps --pull never --entrypoint sh app docker/app/migrate.sh
  fi
fi

# --wait fails for unhealthy/exited services. ML checks model availability in shadow mode.
compose up -d --no-deps --pull never --wait --wait-timeout "$READINESS_TIMEOUT" "${services[@]}"

if ! cmp -s images.env "$candidate" && ! grep -q ':latest$' images.env; then
  previous=$(mktemp "$PWD/.images-previous.XXXXXX")
  cp -- images.env "$previous"
  chmod --reference=images.env "$previous"
  chgrp --reference=images.env "$previous"
  mv -f -- "$previous" images.previous.env
fi
mv -f -- "$candidate" images.env
rm -f -- images.failed.env
echo "Guardian Lab ${group} deployment ready."
# Image cleanup is deliberately left to the server policy. Keep current/previous tags
# available for recovery, and never prune images used by dynamically created sessions.
