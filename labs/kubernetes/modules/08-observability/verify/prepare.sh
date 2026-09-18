#!/usr/bin/env bash
set -euo pipefail

kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab >/dev/null
kubectl -n lab get quota lab-quota >/dev/null 2>&1 || echo "prepare: нет ResourceQuota lab-quota — выполните bash scripts/bootstrap/01-apply-quotas.sh"
kubectl top nodes >/dev/null 2>&1 || { echo "metrics-server не отвечает — установите: bash scripts/bootstrap/02-install-metrics-server.sh"; exit 1; }
echo "prepare: metrics-server отвечает"
