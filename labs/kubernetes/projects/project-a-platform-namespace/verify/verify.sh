#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
kubectl get ns platform >/dev/null || fail "namespace/platform not found"

require_resource platform networkpolicy default-deny
require_resource platform resourcequota platform-quota
require_resource platform limitrange platform-limits
require_resource platform role platform-admin

# Run the audit script
if [ -x "$(dirname "$0")/../audit/namespace-audit.sh" ]; then
  "$(dirname "$0")/../audit/namespace-audit.sh" || fail "Audit script failed"
fi

ok "project-a verified"
