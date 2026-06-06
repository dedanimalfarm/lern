#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab
require_resource lab sts redis
require_resource lab svc redis-headless
require_resource lab cronjob redis-backup

# Run the audit script
if [ -x "$(dirname "$0")/../audit/stateful-audit.sh" ]; then
  "$(dirname "$0")/../audit/stateful-audit.sh" || fail "Audit script failed"
fi

ok "project-b verified"
