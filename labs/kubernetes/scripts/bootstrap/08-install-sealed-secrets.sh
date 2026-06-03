#!/usr/bin/env bash
set -euo pipefail

command -v kubectl &>/dev/null || { echo "kubectl not found"; exit 1; }
kubectl cluster-info --request-timeout=5s &>/dev/null || { echo "cluster not reachable"; exit 1; }

# Pinned Sealed Secrets (контроллер в ns kube-system) для модуля 16.
SS_VERSION="0.37.0"
kubectl apply -f "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${SS_VERSION}/controller.yaml"
kubectl -n kube-system rollout status deploy/sealed-secrets-controller --timeout=180s

# kubeseal CLI (клиент: шифрует Secret -> SealedSecret публичным ключом контроллера).
if ! command -v kubeseal >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  curl -sSL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${SS_VERSION}/kubeseal-${SS_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C "$tmp" kubeseal
  sudo install -m 0755 "$tmp/kubeseal" /usr/local/bin/kubeseal
  rm -rf "$tmp"
fi

echo "sealed-secrets ${SS_VERSION} installed (controller в kube-system) + kubeseal $(kubeseal --version 2>/dev/null | head -1)"
