#!/usr/bin/env bash
set -euo pipefail

helm uninstall demo -n lab >/dev/null 2>&1 || true
helm uninstall demo-app -n lab >/dev/null 2>&1 || true
if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  kubectl -n argocd delete application demo-app --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
  kubectl -n argocd delete appproject labs --ignore-not-found >/dev/null 2>&1 || true
fi
echo "cleanup: готово"
