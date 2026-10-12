#!/usr/bin/env bash
set -euo pipefail
exec python3 -B "$(dirname "$(readlink -f "$0")")/scripts/setup.py" check "$@"
