#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/root/.kube/kubespray.conf}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
need_bin kubectl-argo-rollouts
require_namespace lab
require_resource lab rollout demo-rollout
require_resource lab rollout demo-rollout-bg
require_resource lab svc demo-rollout-svc
require_resource lab svc rollout-active
require_resource lab svc rollout-preview
require_resource lab analysistemplate success-rate

# Ждёт Healthy, САМ проходя ручные паузы promote'ом. Это делает verify
# идемпотентным: если rollout существовал с другим образом, apply манифестов
# запускает новый релиз, который паркуется на pause{} — голый `rollouts
# status --timeout` в этом случае висит до таймаута (ловили в QA).
wait_healthy() {
  local name="$1" phase=""
  for _ in $(seq 1 48); do
    phase=$(kubectl -n lab get rollout "$name" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    case "$phase" in
      Healthy) return 0 ;;
      Paused)  kubectl argo rollouts promote "$name" -n lab >/dev/null 2>&1 || true ;;
      Degraded) fail "rollout $name деградировал: $(kubectl -n lab get rollout "$name" -o jsonpath='{.status.message}')" ;;
    esac
    sleep 5
  done
  fail "rollout $name не стал Healthy за ~4 мин (phase=$phase)"
}

wait_healthy demo-rollout
wait_healthy demo-rollout-bg
ok "оба Rollout здоровы"

# Поведенческая проверка: реальный canary-релиз с метрическим gate'ом.
CUR=$(kubectl -n lab get rollout demo-rollout -o jsonpath='{.spec.template.spec.containers[0].image}')
NEW="argoproj/rollouts-demo:yellow"
[[ "$CUR" == "$NEW" ]] && NEW="argoproj/rollouts-demo:green"
kubectl argo rollouts set image demo-rollout app="$NEW" -n lab >/dev/null
sleep 5
wait_healthy demo-rollout

AR_PHASE=""
for _ in $(seq 1 12); do
  AR_PHASE=$(kubectl -n lab get analysisrun --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].status.phase}' 2>/dev/null || true)
  [[ "$AR_PHASE" == "Successful" ]] && break
  sleep 5
done
[[ "$AR_PHASE" == "Successful" ]] || fail "AnalysisRun не Successful (phase=$AR_PHASE) — метрический gate не отработал"
ok "canary-релиз с Prometheus-анализом доехал до Healthy, AnalysisRun Successful"

ok "module 24 verified"
