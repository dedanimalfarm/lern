#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Порядок критичен из-за вебхуков HNC:
# 1) субнеймспейсы удаляются ТОЛЬКО через якорь и ТОЛЬКО пока HNC жив
#    (без контроллера каскада не будет — ns останется сиротой);
# 2) родительский ns нельзя удалить, пока в нём есть якоря (вебхук откажет);
# 3) сам HNC сносим последним.
if kubectl get ns hnc-system >/dev/null 2>&1; then
  kubectl delete subns team-a-dev -n parent-ns --ignore-not-found 2>/dev/null || true
  for _ in $(seq 1 15); do
    kubectl get ns team-a-dev >/dev/null 2>&1 || break
    sleep 2
  done
fi
# Если HNC уже отсутствует (повторный cleanup) — вебхуков нет, ns удаляются напрямую.
kubectl delete ns team-a-dev m28-child child-ns --ignore-not-found 2>/dev/null || true
kubectl delete ns m28-parent parent-ns billing-app --ignore-not-found 2>/dev/null || true

kubectl delete -f "$MODULE_DIR/manifests/02-hnc.yaml" --ignore-not-found 2>/dev/null || true
kubectl delete -f "$MODULE_DIR/manifests/01-vcluster.yaml" --ignore-not-found 2>/dev/null || true
kubectl -n lab delete pvc data-my-vcluster-0 --ignore-not-found 2>/dev/null || true

echo "cleanup: removed module 28 resources (HNC, vcluster, test namespaces)"
