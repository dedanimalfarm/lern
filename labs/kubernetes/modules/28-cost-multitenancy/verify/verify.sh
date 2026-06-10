#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

# --- 1. HNC: реальная проверка ПОВЕДЕНИЯ (propagation), не наличия объектов ---
require_deployment_ready hnc-system hnc-controller-manager 180s

kubectl create ns m28-parent --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create ns m28-child --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Вебхуки HNC поднимаются чуть позже деплоймента; даём время на готовность.
HC_OK=""
for _ in $(seq 1 15); do
  if kubectl apply -f - >/dev/null 2>&1 <<'YAML'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: HierarchyConfiguration
metadata:
  name: hierarchy
  namespace: m28-child
spec:
  parent: m28-parent
YAML
  then HC_OK=yes; break; fi
  sleep 4
done
[[ -n "$HC_OK" ]] || fail "HNC: не удалось задать parent через HierarchyConfiguration (вебхук не отвечает?)"

kubectl -n m28-parent create rolebinding m28-probe \
  --clusterrole=view --serviceaccount=lab:default \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

PROPAGATED=""
for _ in $(seq 1 20); do
  if kubectl -n m28-child get rolebinding m28-probe >/dev/null 2>&1; then
    PROPAGATED=yes; break
  fi
  sleep 3
done
[[ -n "$PROPAGATED" ]] || fail "HNC: RoleBinding не распространился из m28-parent в m28-child"
ok "HNC: иерархия работает, RBAC распространяется parent -> child"

# --- 2. vcluster: API отвечает, под изнутри синхронизируется в host ---
require_statefulset_ready lab my-vcluster 300s
require_resource lab secret vc-my-vcluster

VCFG=$(mktemp)
kubectl get secret vc-my-vcluster -n lab -o jsonpath='{.data.config}' | base64 -d \
  | sed 's|server: https://.*|server: https://localhost:18443|' > "$VCFG"

kubectl -n lab port-forward svc/my-vcluster 18443:443 >/dev/null 2>&1 &
PF_PID=$!
# shellcheck disable=SC2064
trap "kill $PF_PID >/dev/null 2>&1 || true; rm -f $VCFG" EXIT

VAPI=""
for _ in $(seq 1 20); do
  if kubectl --kubeconfig "$VCFG" get ns >/dev/null 2>&1; then VAPI=yes; break; fi
  sleep 3
done
[[ -n "$VAPI" ]] || fail "vcluster: API не отвечает через port-forward"
ok "vcluster: API доступен"

kubectl --kubeconfig "$VCFG" delete pod m28-probe --ignore-not-found >/dev/null 2>&1
kubectl --kubeconfig "$VCFG" run m28-probe --image=nginx:1.27-alpine \
  --overrides='{"spec":{"containers":[{"name":"m28-probe","image":"nginx:1.27-alpine","resources":{"requests":{"cpu":"20m","memory":"32Mi"},"limits":{"cpu":"100m","memory":"64Mi"}}}]}}' >/dev/null

SYNCED=""
for _ in $(seq 1 30); do
  phase=$(kubectl -n lab get pod m28-probe-x-default-x-my-vcluster -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [[ "$phase" == "Running" ]]; then SYNCED=yes; break; fi
  sleep 3
done
[[ -n "$SYNCED" ]] || fail "vcluster: под изнутри vcluster не появился Running в host-ns lab"
kubectl --kubeconfig "$VCFG" delete pod m28-probe --ignore-not-found >/dev/null 2>&1
ok "vcluster: под из виртуального кластера реально работает в host (syncer)"

ok "module 28 verified"
