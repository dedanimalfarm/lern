#!/usr/bin/env bash
set -euo pipefail

command -v kubectl &>/dev/null || { echo "kubectl not found"; exit 1; }
kubectl cluster-info --request-timeout=5s &>/dev/null || { echo "cluster not reachable"; exit 1; }

# Pinned cert-manager (CRDs + controller + webhook + cainjector) для модуля 22.
CM_VERSION="v1.20.2"
MANIFEST_URL="https://github.com/cert-manager/cert-manager/releases/download/${CM_VERSION}/cert-manager.yaml"

# cert-manager.yaml включает CRD и компоненты в ns cert-manager.
kubectl apply -f "$MANIFEST_URL"

# Ждём ВСЕ три компонента. Особенно важен webhook: пока он не Ready, admission
# отвергает создание Issuer/Certificate ("failed calling webhook"). Поэтому без
# готового webhook делать ClusterIssuer бессмысленно.
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=180s

echo "cert-manager ${CM_VERSION} installed (controller + webhook + cainjector в ns cert-manager)"
