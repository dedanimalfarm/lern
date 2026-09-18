#!/usr/bin/env bash
set -euo pipefail

kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab >/dev/null
kubectl -n lab get quota lab-quota >/dev/null 2>&1 || echo "prepare: нет ResourceQuota lab-quota — выполните bash scripts/bootstrap/01-apply-quotas.sh"
kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' | grep -q . || { echo "Нет default StorageClass — установите: bash scripts/bootstrap/05-install-storage.sh"; exit 1; }
echo "prepare: default StorageClass на месте"
