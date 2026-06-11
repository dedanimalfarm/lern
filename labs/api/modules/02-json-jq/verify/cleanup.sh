#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

rm -f /tmp/api-lab/m02-report.json /tmp/api-lab/m02-open.tsv /tmp/api-lab/m02-payload.json
"$ROOT_DIR/scripts/api.sh" down
echo "[OK] module 02 cleaned"
