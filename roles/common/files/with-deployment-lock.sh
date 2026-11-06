#!/usr/bin/env bash
# One host lock shared by Ansible and every repository's deployment helper.
set -euo pipefail
lock_dir=/opt/docker-stack/.locks
lease="$lock_dir/holder.json"
valid_lease() {
  python3 - "$lease" "${INFRA_LOCK_TOKEN:-}" <<'PY'
import json, os, sys
try:
    holder = json.load(open(sys.argv[1]))
    assert sys.argv[2] and holder['token'] == sys.argv[2]
    os.kill(holder['pid'], 0)
    assert os.path.realpath(f"/proc/{holder['pid']}/fd/8") == '/opt/docker-stack/.locks/deployment.lock'
except (OSError, ValueError, KeyError, AssertionError):
    sys.exit(1)
PY
}
if [[ "${1:-}" == --validate ]]; then
  valid_lease
  exit $?
fi
if valid_lease; then
  exec "$@"
fi
if [[ ! -d "$lock_dir" ]]; then
  sudo -n install -d -m 0770 -o "$(id -un)" -g docker "$lock_dir"
fi
exec 8>"$lock_dir/deployment.lock"
flock -w "${INFRA_LOCK_TIMEOUT:-1800}" 8
export INFRA_LOCK_TOKEN
INFRA_LOCK_TOKEN=$(python3 -c 'import secrets;print(secrets.token_hex(24))')
umask 007
python3 - "$lease" "$$" "$INFRA_LOCK_TOKEN" <<'PY'
import json, os, sys
with open(sys.argv[1], 'w') as f:
    json.dump({'pid':int(sys.argv[2]), 'token':sys.argv[3]}, f)
PY
trap 'rm -f -- "$lease"; rm -rf -- "/opt/docker-stack/.registry/$INFRA_LOCK_TOKEN"' EXIT
if [[ "${1:-}" == --hold ]]; then
  printf 'LOCKED %s\n' "$INFRA_LOCK_TOKEN"
  cat >/dev/null
else
  "$@"
fi
