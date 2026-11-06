#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
python3 scripts/catalog.py plan "$@"
python3 scripts/env-contracts.py github-sync "$@"
exec python3 scripts/deploy.py dns "$@"
