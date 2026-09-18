#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"
MOD="$ROOT_DIR/modules/09-helm-gitops"
CHART_DIR="$MOD/charts/demo-app"

need_bin kubectl
need_bin helm
require_namespace lab

helm lint "$CHART_DIR" >/dev/null || fail "helm lint: чарт demo-app не проходит проверку"
KINDS=$(helm template demo "$CHART_DIR" | grep -E '^kind:' | sort -u | tr '\n' ' ' || true)
for k in ConfigMap Deployment Service Ingress; do
  [[ "$KINDS" == *"kind: $k"* ]] || fail "helm template: в рендере нет $k (есть: $KINDS)"
done
ok "Part 1: lint + template (ConfigMap, Deployment, Service, Ingress)"

helm upgrade --install demo "$CHART_DIR" -n lab --wait --timeout 180s >/dev/null || fail "helm install demo не завершился за 180s"
require_deployment_ready lab demo 120s
STATUS=$(helm status demo -n lab -o json 2>/dev/null | grep -o '"status":"[a-z]*"' | head -1 || true)
[[ "$STATUS" == '"status":"deployed"' ]] || fail "release demo не в статусе deployed: $STATUS"
helm upgrade demo "$CHART_DIR" -n lab --set replicaCount=2 --wait --timeout 180s >/dev/null || fail "helm upgrade --set replicaCount=2 не прошёл"
[[ "$(kubectl -n lab get deploy demo -o jsonpath='{.spec.replicas}')" == "2" ]] || fail "после upgrade ожидали replicas=2"
helm rollback demo 1 -n lab --wait --timeout 180s >/dev/null || fail "helm rollback demo 1 не прошёл"
[[ "$(kubectl -n lab get deploy demo -o jsonpath='{.spec.replicas}')" == "1" ]] || fail "после rollback ожидали replicas=1"
REV=$(helm history demo -n lab -o json 2>/dev/null | grep -o '"revision":[0-9]*' | wc -l || true)
[[ "$REV" -ge 3 ]] || fail "helm history: ожидали >= 3 ревизий (install, upgrade, rollback), есть $REV"
ok "Part 1: install -> upgrade(replicas=2) -> rollback(replicas=1), ревизий: $REV"
helm uninstall demo -n lab >/dev/null 2>&1 || true

if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  kubectl apply -f "$MOD/gitops/argocd/project.yaml" -f "$MOD/gitops/argocd/app.yaml" >/dev/null
  S=""
  for _ in $(seq 1 48); do
    S=$(kubectl -n argocd get application demo-app -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
    [[ "$S" == "Synced/Healthy" ]] && break
    sleep 5
  done
  [[ "$S" == "Synced/Healthy" ]] || fail "Argo CD: demo-app не стал Synced/Healthy за 240s (сейчас: ${S:-?}); conditions: $(kubectl -n argocd get application demo-app -o jsonpath='{.status.conditions[*].message}' 2>/dev/null || true)"
  require_deployment_ready lab demo-app 120s
  kubectl -n lab scale deploy demo-app --replicas=3 >/dev/null
  R=""
  for _ in $(seq 1 24); do
    R=$(kubectl -n lab get deploy demo-app -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
    [[ "$R" == "1" ]] && break
    sleep 5
  done
  [[ "$R" == "1" ]] || fail "selfHeal: replicas после ручного scale=3 не вернулись к 1 за 120s (сейчас: ${R:-?})"
  ok "Part 2: Argo CD demo-app Synced/Healthy, selfHeal вернул replicas=1"
else
  warn "Argo CD не установлен — часть 2 пропущена (bash scripts/bootstrap/06-install-argocd.sh)"
fi

ok "module 09 verified"
