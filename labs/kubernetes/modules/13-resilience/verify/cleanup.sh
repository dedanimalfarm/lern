#!/usr/bin/env bash
set -euo pipefail

echo "Очистка ресурсов модуля 13-resilience..."

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "$DIR/../manifests" ]; then
    kubectl -n lab delete -k "$DIR/../manifests" --ignore-not-found || true
fi

# Универсальная очистка всех возможных ресурсов в ns lab для этого модуля
kubectl -n lab delete deploy,pdb,pod -l app=resilient-app --ignore-not-found || true

# Восстановление состояния нод (если студент забыл сделать uncordon)
echo "Восстановление состояния нод (uncordon)..."
for node in $(kubectl get nodes -o name); do
    kubectl uncordon "$node" >/dev/null 2>&1 || true
done

echo "Уборка завершена."
