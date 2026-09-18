#!/usr/bin/env bash
set -euo pipefail

kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab >/dev/null
kubectl -n lab get quota lab-quota >/dev/null 2>&1 || echo "prepare: нет ResourceQuota lab-quota — выполните bash scripts/bootstrap/01-apply-quotas.sh"
command -v helm >/dev/null 2>&1 || { echo "Нужен helm (https://helm.sh/docs/intro/install/)"; exit 1; }
kubectl get crd applications.argoproj.io >/dev/null 2>&1 || echo "prepare: Argo CD не установлен — часть 2 в verify будет пропущена: bash scripts/bootstrap/06-install-argocd.sh"
helm uninstall demo -n lab >/dev/null 2>&1 || true
echo "prepare: helm на месте"
