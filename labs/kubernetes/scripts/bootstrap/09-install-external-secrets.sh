#!/usr/bin/env bash
set -euo pipefail
command -v kubectl &>/dev/null || { echo "kubectl not found"; exit 1; }
command -v helm   &>/dev/null || { echo "helm not found";   exit 1; }
kubectl cluster-info --request-timeout=5s &>/dev/null || { echo "cluster not reachable"; exit 1; }

# External Secrets Operator (модуль 16, Часть 3). API: external-secrets.io/v1 (GA).
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --wait --timeout 5m

echo "external-secrets installed (ns external-secrets); API group external-secrets.io/v1"
