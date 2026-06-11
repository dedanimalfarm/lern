#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

rm -f /tmp/api-lab/m06-diagnosis.txt /tmp/api-lab/.m06-actual \
      /tmp/api-lab/m06-escalation.md
"$ROOT_DIR/scripts/api.sh" sink-down
"$ROOT_DIR/scripts/api.sh" down
echo "[OK] module 06 cleaned"
