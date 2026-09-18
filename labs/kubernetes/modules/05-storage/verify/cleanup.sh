#!/usr/bin/env bash
set -euo pipefail

kubectl -n lab delete sts,deploy,pod --all --ignore-not-found >/dev/null 2>&1 || true
kubectl -n lab delete pvc --all --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
kubectl delete pv static-pv-demo --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
for pv in $(kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="lab")]}{.metadata.name}{" "}{end}' 2>/dev/null || true); do
  kubectl delete pv "$pv" --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
done
echo "cleanup: готово"
