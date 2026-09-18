#!/usr/bin/env bash
set -euo pipefail

kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab >/dev/null
kubectl -n lab get quota lab-quota >/dev/null 2>&1 || echo "prepare: нет ResourceQuota lab-quota — выполните bash scripts/bootstrap/01-apply-quotas.sh"
kubectl get ingressclass nginx >/dev/null 2>&1 || echo "prepare: нет IngressClass nginx — часть про Ingress не отработает: bash scripts/bootstrap/03-install-ingress.sh"
echo "prepare: namespace lab готов"
