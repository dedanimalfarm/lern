#!/usr/bin/env bash
set -euo pipefail

echo "Cleaning up module 18 resources..."

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$DIR/../manifests"

if [ -d "$MANIFESTS_DIR" ]; then
  kubectl delete -f "$MANIFESTS_DIR" --ignore-not-found=true
else
  echo "[WARNING] Manifests directory not found at $MANIFESTS_DIR. Skipping 'kubectl delete -f'."
fi

# Wait for deployments to be completely removed
kubectl -n lab wait --for=delete pod -l app=loki --timeout=60s || true
kubectl -n lab wait --for=delete pod -l app=promtail --timeout=60s || true
kubectl -n lab wait --for=delete pod -l app=payment-api --timeout=60s || true
kubectl -n lab wait --for=delete pod -l app=log-generator --timeout=60s || true

# Explicitly cleanup cluster-wide and cross-namespace resources just in case
kubectl delete clusterrole promtail-role --ignore-not-found=true
kubectl delete clusterrolebinding promtail-binding --ignore-not-found=true
kubectl -n monitoring delete secret loki-datasource --ignore-not-found=true

# Also remove configmaps and service account manually if missed
kubectl -n lab delete configmap loki-config promtail-config --ignore-not-found=true
kubectl -n lab delete serviceaccount promtail --ignore-not-found=true

echo "[OK] Module 18 cleaned up."
