#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl

# ApplicationSet существует (источник всех трёх Application).
require_resource argocd applicationset web-environments
ok "applicationset/web-environments present"

# AppProject границ доверия создан.
require_resource argocd appproject labs-gitops
ok "appproject/labs-gitops present"

# Каждое окружение: Application сгенерирован, Synced + Healthy; Deployment с нужным
# числом реплик развёрнут в своём namespace. Ждём, пока Argo синхронизирует.
declare -A WANT=( [dev]=1 [staging]=2 [prod]=3 )
for env in dev staging prod; do
  app="web-$env"
  ns="lab-$env"
  require_resource argocd application "$app"

  # Ждём Synced+Healthy (Argo тянет из git и применяет).
  for _ in $(seq 1 90); do
    sync=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
    health=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.health.status}' 2>/dev/null || true)
    [[ "$sync" == "Synced" && "$health" == "Healthy" ]] && break
    sleep 2
  done
  [[ "$sync" == "Synced" ]] || fail "application/$app sync='$sync', expected Synced"
  [[ "$health" == "Healthy" ]] || fail "application/$app health='$health', expected Healthy"

  # Deployment развёрнут с правильным числом реплик именно для этого окружения.
  require_deployment_ready "$ns" web 120s
  got=$(kubectl -n "$ns" get deploy web -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
  [[ "$got" == "${WANT[$env]}" ]] || fail "deploy web in $ns replicas=$got, expected ${WANT[$env]}"
  ok "$app Synced/Healthy, deploy web in $ns has ${WANT[$env]} replica(s)"
done

ok "module 25 verified"
