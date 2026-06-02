#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab
require_deployment_ready lab hpa-demo 120s
require_resource lab hpa hpa-demo

# HPA должен ВИДЕТЬ метрику (не <unknown>): значит requests.cpu задан и
# metrics-server отдаёт данные. currentMetrics появляется через ~15-60с.
UTIL=$(kubectl -n lab get hpa hpa-demo -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)
if [[ -n "$UTIL" ]]; then
  ok "hpa-demo metric available (current CPU utilization = ${UTIL}%)"
else
  warn "hpa-demo metric <unknown> — подождите прогрев metrics-server или проверьте requests.cpu"
fi

ok "module 11 verified"
