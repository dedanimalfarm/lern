#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"
MOD="$ROOT_DIR/modules/16-secrets-management"

need_bin kubectl
require_namespace lab

echo "Verifying Module 16: Secrets Management..."

# 1. Check Sealed Secrets
if kubectl -n kube-system get deploy sealed-secrets-controller >/dev/null 2>&1; then
  require_deployment_ready kube-system sealed-secrets-controller 120s
  if [ -f "$MOD/manifests/sealed/sealed-secret.yaml" ]; then
    kubectl apply -f "$MOD/manifests/sealed/sealed-secret.yaml" >/dev/null
    for _ in $(seq 1 10); do kubectl -n lab get secret app-creds >/dev/null 2>&1 && break; sleep 2; done
    require_resource lab secret app-creds
    GOT=$(kubectl -n lab get secret app-creds -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
    [[ "$GOT" == "S3cr3tP@ss" ]] || fail "SealedSecret unseal: password='$GOT', expected 'S3cr3tP@ss' (этот SealedSecret привязан к ДРУГОМУ кластеру? перегенерируйте kubeseal)"
    ok "Part 2: SealedSecret successfully unsealed to Secret/app-creds"
  else
    fail "sealed-secret.yaml not found"
  fi
else
  fail "sealed-secrets-controller is missing (run bootstrap/08-install-sealed-secrets.sh)"
fi

# 2. Check External Secrets Operator (ESO)
if kubectl get crd externalsecrets.external-secrets.io >/dev/null 2>&1; then
  ESO_DEPLOY=$(kubectl -n external-secrets get deploy -l app.kubernetes.io/name=external-secrets -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "external-secrets")
  require_deployment_ready external-secrets "$ESO_DEPLOY" 120s
  ok "Part 3: External Secrets Operator is installed and running"
else
  fail "ESO is not installed (run bootstrap/09-install-external-secrets.sh)"
fi

# 3. Check Vault Secrets Operator (VSO)
if kubectl get crd vaultdynamicsecrets.secrets.hashicorp.com >/dev/null 2>&1; then
  VSO_DEPLOY=$(kubectl -n vault-secrets-operator-system get deploy -l app.kubernetes.io/name=vault-secrets-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "vso-vault-secrets-operator")
  require_deployment_ready vault-secrets-operator-system "$VSO_DEPLOY" 120s
  ok "Part 4: Vault Secrets Operator is installed and running"
else
  fail "VSO is not installed (run bootstrap/10-install-vault-secrets-operator.sh)"
fi

# 4. Check Vault & Postgres deployments in lab namespace
if kubectl -n lab get deploy vault >/dev/null 2>&1 && kubectl -n lab get deploy pg >/dev/null 2>&1; then
  require_deployment_ready lab vault 120s
  require_deployment_ready lab pg 120s
  ok "Vault and Postgres deployments are running"
  
  if kubectl -n lab get vaultdynamicsecret pg-dynamic-creds >/dev/null 2>&1; then
    require_resource lab secret pg-dynamic-creds
    GOT_USER=$(kubectl -n lab get secret pg-dynamic-creds -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || true)
    [[ -n "$GOT_USER" ]] || fail "Dynamic secret pg-dynamic-creds has no username"
    ok "VaultDynamicSecret generated dynamic credentials in Secret/pg-dynamic-creds ($GOT_USER)"
  else
    warn "VaultDynamicSecret 'pg-dynamic-creds' not found. Student might not have completed Part 4."
  fi
else
  warn "Vault or Postgres not found in 'lab' namespace. Student might not have completed Part 4."
fi

ok "module 16 verified"
