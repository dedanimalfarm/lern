#!/usr/bin/env bash
# SealedSecret привязан к ключевой паре КОНКРЕТНОГО кластера: kubeseal шифрует
# публичным ключом контроллера, и после пересоздания кластера (новый ключ)
# закоммиченный manifests/sealed/sealed-secret.yaml расшифровать невозможно.
# Этот prepare самовосстанавливает модуль: если контроллер не разворачивает
# Secret из текущего файла — перегенерирует SealedSecret под живой кластер
# (тогда обновлённый файл стоит закоммитить).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SEALED="$ROOT_DIR/modules/16-secrets-management/manifests/sealed/sealed-secret.yaml"

unsealed() {
  for _ in $(seq 1 10); do
    kubectl -n lab get secret app-creds >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

kubectl apply -f "$SEALED" >/dev/null
if unsealed; then
  exit 0
fi

echo "SealedSecret не расшифрован контроллером (ключ другого кластера) — перегенерирую через kubeseal"
command -v kubeseal >/dev/null || { echo "kubeseal не установлен (см. scripts/bootstrap/08)"; exit 1; }
kubectl -n lab delete sealedsecret app-creds --ignore-not-found >/dev/null
kubectl -n lab create secret generic app-creds \
  --from-literal=username=appuser --from-literal=password='S3cr3tP@ss' \
  --dry-run=client -o yaml \
  | kubeseal --controller-namespace kube-system -o yaml > "$SEALED"
kubectl apply -f "$SEALED" >/dev/null

if ! unsealed; then
  echo "sealed-secrets controller так и не создал Secret/app-creds" >&2
  exit 1
fi
echo "SealedSecret перегенерирован под текущий кластер: $SEALED (закоммитьте обновлённый файл)"
