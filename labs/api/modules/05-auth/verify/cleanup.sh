#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

rm -f /tmp/api-lab/m05-token.txt /tmp/api-lab/m05-jwt-payload.json \
      /tmp/api-lab/m05-403.txt /tmp/api-lab/m05-my-tickets.json
# вернуть стенд в дефолтный режим (без аутентификации)
"$ROOT_DIR/scripts/api.sh" up >/dev/null
"$ROOT_DIR/scripts/api.sh" down
echo "[OK] module 05 cleaned"
