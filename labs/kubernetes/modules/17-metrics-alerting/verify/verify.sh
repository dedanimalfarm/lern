#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab
require_deployment_ready lab metrics-app 120s
require_resource lab servicemonitor metrics-app

# Стек kube-prometheus-stack должен быть установлен (ns monitoring + prometheus)
if kubectl get ns monitoring >/dev/null 2>&1 \
   && kubectl -n monitoring get pods 2>/dev/null | grep -qiE "prometheus-kps|prometheus-.*-0"; then
  ok "kube-prometheus-stack present (ns monitoring)"
else
  warn "kube-prometheus-stack не найден — установите его (см. README, Часть 1)"
fi

ok "module 17 verified"
