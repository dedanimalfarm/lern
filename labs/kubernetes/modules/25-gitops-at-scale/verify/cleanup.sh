#!/usr/bin/env bash
set -euo pipefail

if kubectl get crd applicationsets.argoproj.io >/dev/null 2>&1; then
  kubectl -n argocd delete applicationset web-environments --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n argocd delete application web-dev web-staging web-prod --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
  kubectl -n argocd delete appproject labs-gitops --ignore-not-found >/dev/null 2>&1 || true
fi
kubectl delete ns lab-dev lab-staging lab-prod --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
echo "cleanup: готово"
