#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"
MOD="$ROOT_DIR/modules/16-secrets-management"

need_bin kubectl
require_namespace lab

# Часть 2 (детерминированное ядро): SealedSecret -> контроллер создаёт обычный Secret.
if kubectl -n kube-system get deploy sealed-secrets-controller >/dev/null 2>&1; then
  require_deployment_ready kube-system sealed-secrets-controller 120s
  kubectl apply -f "$MOD/manifests/sealed/sealed-secret.yaml" >/dev/null
  for _ in $(seq 1 10); do kubectl -n lab get secret app-creds >/dev/null 2>&1 && break; sleep 2; done
  require_resource lab secret app-creds
  GOT=$(kubectl -n lab get secret app-creds -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
  [[ "$GOT" == "S3cr3tP@ss" ]] || fail "SealedSecret unseal: password='$GOT', expected 'S3cr3tP@ss' (этот SealedSecret привязан к ДРУГОМУ кластеру? перегенерируйте kubeseal)"
  ok "Sealed Secrets: SealedSecret -> Secret/app-creds расшифрован контроллером"
else
  fail "sealed-secrets-controller не установлен (scripts/bootstrap/08-install-sealed-secrets.sh)"
fi

# Часть 3 (мягко): External Secrets Operator установлен.
if kubectl get crd externalsecrets.external-secrets.io >/dev/null 2>&1; then
  ok "External Secrets Operator присутствует (CRD external-secrets.io)"
else
  warn "ESO не установлен — Часть 3 пропущена (scripts/bootstrap/09-install-external-secrets.sh)"
fi

# Часть 4 (мягко): Vault Secrets Operator установлен.
if kubectl get crd vaultdynamicsecrets.secrets.hashicorp.com >/dev/null 2>&1; then
  ok "Vault Secrets Operator присутствует (CRD secrets.hashicorp.com)"
else
  warn "VSO не установлен — Часть 4 пропущена (scripts/bootstrap/10-install-vault-secrets-operator.sh)"
fi

ok "module 16 verified"
