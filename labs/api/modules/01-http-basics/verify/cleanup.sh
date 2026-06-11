#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

rm -f /tmp/api-lab/m01-headers.txt /tmp/api-lab/m01-codes.txt
"$ROOT_DIR/scripts/api.sh" down
echo "[OK] module 01 cleaned"
