#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

rm -f /tmp/api-lab/m03-docs.txt /tmp/api-lab/m03-ids.txt
"$ROOT_DIR/scripts/api.sh" down
echo "[OK] module 03 cleaned"
