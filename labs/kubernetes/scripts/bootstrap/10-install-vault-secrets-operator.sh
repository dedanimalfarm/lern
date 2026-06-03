#!/usr/bin/env bash
set -euo pipefail
command -v kubectl &>/dev/null || { echo "kubectl not found"; exit 1; }
command -v helm   &>/dev/null || { echo "helm not found";   exit 1; }
kubectl cluster-info --request-timeout=5s &>/dev/null || { echo "cluster not reachable"; exit 1; }

# HashiCorp Vault Secrets Operator (модуль 16, Часть 4 — VaultDynamicSecret).
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo update hashicorp >/dev/null
helm upgrade --install vso hashicorp/vault-secrets-operator \
  -n vault-secrets-operator-system --create-namespace --wait --timeout 5m

echo "vault-secrets-operator installed (ns vault-secrets-operator-system); CRD secrets.hashicorp.com (VaultConnection/VaultAuth/VaultDynamicSecret)"
