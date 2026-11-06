#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
if [[ "${1:-}" == --all && $# == 1 ]]; then
  exec python3 scripts/deploy.py all
fi
exec python3 scripts/deploy.py deploy "$@"
