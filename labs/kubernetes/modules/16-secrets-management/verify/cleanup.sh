#!/usr/bin/env bash
set -euo pipefail

echo "Cleaning up Module 16 resources..."

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. Delete module-specific resources in lab namespace
kubectl -n lab delete -f "$DIR/manifests/vault/vso-secrets.yaml" --ignore-not-found
kubectl -n lab delete -f "$DIR/manifests/vault/vault-pg.yaml" -f "$DIR/manifests/vault/rbac.yaml" --ignore-not-found
kubectl -n lab delete -f "$DIR/manifests/eso/eso-fake.yaml" --ignore-not-found
kubectl -n lab delete sealedsecret app-creds --ignore-not-found
kubectl -n lab delete secret app-creds pg-dynamic-creds db-from-eso etcd-probe --ignore-not-found
kubectl delete clusterrolebinding vault-token-reviewer --ignore-not-found

# 2. Uninstall Sealed Secrets
echo "Removing Sealed Secrets..."
kubectl -n kube-system delete deploy sealed-secrets-controller --ignore-not-found
kubectl -n kube-system delete service sealed-secrets-controller --ignore-not-found
kubectl -n kube-system delete role sealed-secrets-key-admin --ignore-not-found
kubectl -n kube-system delete rolebinding sealed-secrets-controller --ignore-not-found
kubectl -n kube-system delete serviceaccount sealed-secrets-controller --ignore-not-found
kubectl delete crd sealedsecrets.bitnami.com --ignore-not-found

# 3. Uninstall External Secrets Operator
echo "Removing External Secrets Operator..."
if command -v helm &>/dev/null; then
  helm uninstall external-secrets -n external-secrets 2>/dev/null || true
fi
kubectl delete ns external-secrets --ignore-not-found
kubectl delete crd \
  externalsecrets.external-secrets.io \
  clustersecretstores.external-secrets.io \
  secretstores.external-secrets.io \
  pushsecrets.external-secrets.io \
  clusterexternalsecrets.external-secrets.io \
  generators.external-secrets.io \
  clustergenerators.external-secrets.io --ignore-not-found
kubectl delete validatingwebhookconfiguration external-secrets-validate --ignore-not-found

# 4. Uninstall Vault Secrets Operator
echo "Removing Vault Secrets Operator..."
if command -v helm &>/dev/null; then
  helm uninstall vso -n vault-secrets-operator-system 2>/dev/null || true
fi
kubectl delete ns vault-secrets-operator-system --ignore-not-found
kubectl delete crd \
  vaultconnections.secrets.hashicorp.com \
  vaultauths.secrets.hashicorp.com \
  vaultdynamicsecrets.secrets.hashicorp.com \
  vaultpkisecrets.secrets.hashicorp.com \
  vaultstaticsecrets.secrets.hashicorp.com --ignore-not-found
kubectl delete validatingwebhookconfiguration vso-validating-webhook-configuration --ignore-not-found
kubectl delete mutatingwebhookconfiguration vso-mutating-webhook-configuration --ignore-not-found

echo "Cleanup complete."
