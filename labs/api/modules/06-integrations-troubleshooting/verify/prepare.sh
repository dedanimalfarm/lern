#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

"$ROOT_DIR/scripts/api.sh" sink-up
WEBHOOK_URL=http://127.0.0.1:9100/hook "$ROOT_DIR/scripts/api.sh" up
curl -s -X POST http://127.0.0.1:9100/_reset >/dev/null
curl -s -X POST http://127.0.0.1:8080/api/v1/_lab/reset \
  -H 'Content-Type: application/json' -d '{}' >/dev/null
mkdir -p /tmp/api-lab
echo "[OK] module 06 prepared (стенд с вебхуками + sink, журналы чистые)"
