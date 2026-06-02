#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab
require_deployment_ready lab resilient-app 120s
require_resource lab pdb resilient-app-pdb

# реплики должны быть распределены минимум на 2 разные ноды
NODES=$(kubectl -n lab get pods -l app=resilient-app \
  -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | grep -c . || echo 0)
if [[ "${NODES:-0}" -ge 2 ]]; then
  ok "resilient-app spread across $NODES nodes"
else
  warn "resilient-app on $NODES node(s) — для спреда нужно >=2 нод в кластере"
fi

ok "module 13 verified"
