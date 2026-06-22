#!/usr/bin/env bash
set -euo pipefail

echo "Cleaning up resources for module 15 (NetworkPolicy)..."

# Delete network policies first
kubectl -n lab delete netpol --all --ignore-not-found 2>/dev/null || true

# Delete app manifests
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$ROOT_DIR/manifests/app.yaml" ]; then
  kubectl -n lab delete -f "$ROOT_DIR/manifests/app.yaml" --ignore-not-found 2>/dev/null || true
fi

# Fallback cleanup for any remaining deployments, services, pods
kubectl -n lab delete deploy,svc,pod --all --ignore-not-found 2>/dev/null || true

echo "[OK] Cleanup completed."
