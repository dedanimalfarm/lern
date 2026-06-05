#!/usr/bin/env bash
set -euo pipefail

MODULE_PATH="${1:-}"
if [[ -z "$MODULE_PATH" ]]; then
  echo "usage: $0 modules/<module-name>"
  exit 1
fi

if [[ -f "$MODULE_PATH/manifests/kustomization.yaml" || -f "$MODULE_PATH/manifests/kustomization.yml" ]]; then
  kubectl -n lab delete -k "$MODULE_PATH/manifests" --ignore-not-found=true || true
else
  kubectl -n lab delete -f "$MODULE_PATH/manifests" --ignore-not-found=true || true
fi
kubectl -n lab delete -f "$MODULE_PATH/broken" --ignore-not-found=true 2>/dev/null || true
kubectl -n lab delete -f "$MODULE_PATH/solutions" --ignore-not-found=true 2>/dev/null || true

if [[ -f "$MODULE_PATH/verify/cleanup.sh" ]]; then
  bash "$MODULE_PATH/verify/cleanup.sh" || true
fi

echo "cleaned resources for $MODULE_PATH"
