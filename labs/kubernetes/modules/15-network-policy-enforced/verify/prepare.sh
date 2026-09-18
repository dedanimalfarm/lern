#!/usr/bin/env bash
set -euo pipefail

kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab >/dev/null
kubectl -n lab get quota lab-quota >/dev/null 2>&1 || echo "prepare: нет ResourceQuota lab-quota — выполните bash scripts/bootstrap/01-apply-quotas.sh"
kubectl -n kube-system get ds calico-node >/dev/null 2>&1 || { echo "Calico не найден: без CNI с поддержкой NetworkPolicy трафик не режется — модуль теряет смысл"; exit 1; }
echo "prepare: Calico на месте, NetworkPolicy будет enforced"
