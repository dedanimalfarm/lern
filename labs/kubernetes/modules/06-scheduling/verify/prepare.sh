#!/usr/bin/env bash
set -euo pipefail

# 1) find worker nodes
NODE_A=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
NODE_B=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[1].metadata.name}' 2>/dev/null || true)

# Однонодовые кластеры (kind в CI): воркеров нет, метку disktype=ssd вешаем
# на control-plane — у kind он БЕЗ NoSchedule-taint, поды туда планируются.
# Без fallback'а deployment select-by-label вечно Pending и verify валится.
# NODE_B (taint-демо) на одной ноде не трогаем — затейнтить единственную
# ноду значит сломать всё остальное.
if [[ -z "$NODE_A" ]]; then
  NODE_A=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi

if [[ -n "$NODE_A" ]]; then
  echo "Preparing node A: $NODE_A"
  kubectl label node "$NODE_A" disktype=ssd --overwrite
fi

if [[ -n "$NODE_B" ]]; then
  echo "Preparing node B: $NODE_B"
  kubectl taint node "$NODE_B" dedicated=lab:NoSchedule --overwrite || true
fi
