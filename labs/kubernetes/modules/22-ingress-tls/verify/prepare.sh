#!/usr/bin/env bash
# Fail-fast по пререквизит-аддонам: тяжёлые компоненты — контракт стенда
# (ставятся scripts/cluster/up.sh --addons), а не каждого прогона модуля.
# Без этой проверки verify падал бы поздно и с невнятной диагностикой.
set -euo pipefail

kubectl get ingressclass nginx >/dev/null 2>&1 || {
  echo "Нет IngressClass 'nginx' — установите контроллер:"
  echo "  bash scripts/bootstrap/03-install-ingress.sh"
  exit 1
}
kubectl get crd certificates.cert-manager.io >/dev/null 2>&1 || {
  echo "Нет cert-manager — установите:"
  echo "  bash scripts/bootstrap/07-install-cert-manager.sh"
  exit 1
}
echo "prepare: ingress-nginx + cert-manager на месте"
