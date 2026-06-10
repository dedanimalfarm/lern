#!/usr/bin/env bash
# Fail-fast: модулю нужен предустановленный Argo CD с ApplicationSet-контроллером
# (контракт стенда, scripts/cluster/up.sh --addons). Ставить Argo на каждый
# прогон слишком дорого, а без него verify падает поздно и непонятно.
set -euo pipefail

kubectl get crd applicationsets.argoproj.io >/dev/null 2>&1 || {
  echo "Нет Argo CD (CRD applicationsets.argoproj.io) — установите:"
  echo "  bash scripts/bootstrap/06-install-argocd.sh"
  exit 1
}
kubectl -n argocd get deploy argocd-applicationset-controller >/dev/null 2>&1 || {
  echo "Argo CD есть, но applicationset-controller не найден в ns argocd."
  exit 1
}
echo "prepare: Argo CD + ApplicationSet-контроллер на месте"
