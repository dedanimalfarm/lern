#!/usr/bin/env bash
set -euo pipefail

echo "=== Running module 22 cleanup ==="

echo "[INFO] Deleting lab namespace..."
kubectl delete ns lab --ignore-not-found

# Удаляем ТОЛЬКО ресурс, созданный модулем (ClusterIssuer). ingress-nginx и
# cert-manager — PERSISTENT-аддоны стенда (ставятся scripts/cluster/up.sh --addons,
# общие для модулей 04/09/22/25 и capstone). Их НЕЛЬЗЯ сносить в cleanup модуля:
# раньше этот скрипт удалял ns ingress-nginx + cert-manager (+ CRD), из-за чего
# после прогона m22 все зависящие модули падали («controller not found»,
# «resource type clusterissuer»), а полный sweep давал каскад ложных FAIL.
echo "[INFO] Deleting module-owned ClusterIssuer..."
kubectl delete clusterissuer selfsigned-issuer --ignore-not-found

echo "[OK] Cleanup complete (persistent-аддоны ingress-nginx/cert-manager сохранены)."
