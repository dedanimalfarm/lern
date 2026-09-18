#!/usr/bin/env bash
set -euo pipefail

kubectl -n lab delete pod load --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
kubectl -n lab delete hpa,vpa,deploy,svc --all --ignore-not-found >/dev/null 2>&1 || true
helm uninstall vpa -n vpa >/dev/null 2>&1 || true
kubectl delete ns vpa --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
kubectl delete crd verticalpodautoscalers.autoscaling.k8s.io verticalpodautoscalercheckpoints.autoscaling.k8s.io --ignore-not-found >/dev/null 2>&1 || true
echo "cleanup: готово"
