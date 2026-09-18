#!/usr/bin/env bash
set -euo pipefail

kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab >/dev/null
kubectl -n lab get quota lab-quota >/dev/null 2>&1 || echo "prepare: нет ResourceQuota lab-quota — выполните bash scripts/bootstrap/01-apply-quotas.sh"
kubectl top nodes >/dev/null 2>&1 || { echo "metrics-server не отвечает — установите: bash scripts/bootstrap/02-install-metrics-server.sh"; exit 1; }
if ! kubectl get crd verticalpodautoscalers.autoscaling.k8s.io >/dev/null 2>&1; then
  command -v helm >/dev/null 2>&1 || { echo "Нужен helm для установки VPA"; exit 1; }
  helm repo add fairwinds-stable https://charts.fairwinds.com/stable >/dev/null 2>&1 || true
  helm repo update fairwinds-stable >/dev/null
  helm upgrade --install vpa fairwinds-stable/vpa -n vpa --create-namespace \
    --set updater.enabled=false --set admissionController.enabled=false \
    --wait --timeout 5m
fi
kubectl -n lab delete pod load --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
echo "prepare: metrics-server отвечает, VPA (recommender) установлен"
