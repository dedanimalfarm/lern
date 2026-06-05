#!/usr/bin/env bash
set -euo pipefail

MODULE_PATH="${1:-}"
if [[ -z "$MODULE_PATH" ]]; then
  echo "usage: $0 modules/<module-name>"
  exit 1
fi

if [[ -f "$MODULE_PATH/manifests/kustomization.yaml" || -f "$MODULE_PATH/manifests/kustomization.yml" ]]; then
  kubectl -n lab delete -k "$MODULE_PATH/manifests" --ignore-not-found=true || true
else
  kubectl -n lab delete -f "$MODULE_PATH/manifests" --ignore-not-found=true || true
fi
kubectl -n lab delete -f "$MODULE_PATH/broken" --ignore-not-found=true 2>/dev/null || true
kubectl -n lab delete -f "$MODULE_PATH/solutions" --ignore-not-found=true 2>/dev/null || true

if [[ -f "$MODULE_PATH/verify/cleanup.sh" ]]; then
  bash "$MODULE_PATH/verify/cleanup.sh" || true
fi

# --- Generic safety-net ---------------------------------------------------
# Подчищает типовой residue, который `delete all` и удаление манифестов
# пропускают (secret/netpol/CR/VAP/доп-namespaces/Argo-объекты). Идемпотентно,
# тихо, не трогает persistent-аддоны и системные default-объекты (SA default,
# kube-root-ca CM не удаляем). Делает sweep по-настоящему «чистым после себя».

# 1) CR-источники секретов модуля 16 (ESO/VSO/sealed-secrets) — ПЕРЕД секретами,
#    иначе оператор пересоздаст секрет. Только если соответствующий CRD установлен.
for cr in externalsecrets.external-secrets.io secretstores.external-secrets.io \
          sealedsecrets.bitnami.com vaultstaticsecrets.secrets.hashicorp.com \
          vaultauths.secrets.hashicorp.com vaultconnections.secrets.hashicorp.com; do
  if kubectl get crd "$cr" >/dev/null 2>&1; then
    kubectl -n lab delete "$cr" --all --ignore-not-found=true 2>/dev/null || true
  fi
done

# 2) Namespaced ресурсы в lab, не покрытые `all` (НЕ трогаем default SA / kube-root-ca CM).
kubectl -n lab delete networkpolicy,secret,role,rolebinding,pvc,ingress,resourcequota,limitrange \
  --all --ignore-not-found=true 2>/dev/null || true

# 3) Cluster-scoped ValidatingAdmissionPolicy + биндинги (модуль 14 и capstone E).
kubectl delete validatingadmissionpolicybinding \
  no-latest-tag-binding require-tenant-labels-binding tenant-no-latest-tag-binding \
  --ignore-not-found=true 2>/dev/null || true
kubectl delete validatingadmissionpolicy \
  no-latest-tag require-tenant-labels tenant-no-latest-tag \
  --ignore-not-found=true 2>/dev/null || true

# 4) Argo CD объекты, созданные модулями 25 / capstone F (живут в ns argocd).
if kubectl get ns argocd >/dev/null 2>&1; then
  kubectl -n argocd delete applicationset web-environments --ignore-not-found=true 2>/dev/null || true
  kubectl -n argocd delete appproject labs-gitops --ignore-not-found=true 2>/dev/null || true
  kubectl -n argocd delete application incident-app web-dev web-staging web-prod \
    --ignore-not-found=true 2>/dev/null || true
fi

# 5) Доп. namespaces окружений/тенантов (модуль 25 / project-e secure-platform).
kubectl delete ns lab-dev lab-staging lab-prod tenant-a tenant-b \
  --ignore-not-found=true --wait=false 2>/dev/null || true
# -------------------------------------------------------------------------

echo "cleaned resources for $MODULE_PATH"
