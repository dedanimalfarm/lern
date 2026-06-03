#!/usr/bin/env bash
set -euo pipefail

command -v kubectl &>/dev/null || { echo "kubectl not found"; exit 1; }
kubectl cluster-info --request-timeout=5s &>/dev/null || { echo "cluster not reachable"; exit 1; }

# Pinned Argo CD release for reproducible labs (модуль 09 GitOps)
ARGOCD_VERSION="v3.4.3"
MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

kubectl create ns argocd --dry-run=client -o yaml | kubectl apply -f -

# ВАЖНО: только --server-side. Обычный `kubectl apply` пишет весь манифест в
# аннотацию last-applied-configuration, а CRD applicationsets.argoproj.io > 256KB
# -> "metadata.annotations: Too long: may not be more than 262144 bytes" и CRD не
# создаётся. Server-side apply не использует эту аннотацию (поле management через
# managedFields на сервере) и применяет крупные CRD корректно.
kubectl apply -n argocd --server-side --force-conflicts -f "$MANIFEST_URL"

# Ждём core-компоненты, без которых нет синхронизации:
# repo-server (рендерит Helm/манифесты из Git), application-controller (reconcile),
# redis (кэш). server/dex/applicationset — для UI/SSO/генераторов, для CLI-less
# sync не обязательны.
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-redis --timeout=180s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo "Argo CD ${ARGOCD_VERSION} installed in ns/argocd"
echo "UI (опц.): kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo "admin-пароль: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
