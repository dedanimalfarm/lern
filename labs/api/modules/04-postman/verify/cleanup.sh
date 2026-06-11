#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

rm -f /tmp/api-lab/m04-collection.json /tmp/api-lab/m04-fixed-collection.json
"$ROOT_DIR/scripts/api.sh" down
echo "[OK] module 04 cleaned"
