#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/root/.kube/kubespray.conf

TARGET_PATH="${1:-}"
if [[ -z "$TARGET_PATH" ]]; then
  echo "usage: $0 modules/<module-name>|projects/<project-name>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FULL_PATH="$ROOT_DIR/$TARGET_PATH"

if [[ ! -d "$FULL_PATH" ]]; then
  echo "Directory not found: $FULL_PATH"
  exit 1
fi

echo "--- Running module: $TARGET_PATH ---"

# Prepare
if [[ -f "$FULL_PATH/verify/prepare.sh" ]]; then
  echo "Running prepare.sh..."
  bash "$FULL_PATH/verify/prepare.sh"
fi

# Deploy
if [[ -d "$FULL_PATH/manifests" ]]; then
  if [[ -f "$FULL_PATH/manifests/kustomization.yaml" || -f "$FULL_PATH/manifests/kustomization.yml" ]]; then
    kubectl apply -k "$FULL_PATH/manifests"
  else
    kubectl apply -f "$FULL_PATH/manifests" -R
  fi
elif [[ -d "$FULL_PATH/applicationset" ]]; then
  kubectl apply -k "$FULL_PATH/applicationset" || kubectl apply -f "$FULL_PATH/applicationset"
elif [[ -d "$FULL_PATH/overlays/prod" ]]; then
  kubectl apply -k "$FULL_PATH/overlays/prod"
fi

# Wait a bit for resources to be created in API server
sleep 5

# Verify
set +e
bash "$FULL_PATH/verify/verify.sh"
VERIFY_EXIT=$?
set -e

# Clean
# Some modules use different namespaces, but clean-all/clean-module handles 'lab'
if [[ -x "$ROOT_DIR/scripts/clean/clean-module.sh" ]]; then
  bash "$ROOT_DIR/scripts/clean/clean-module.sh" "$TARGET_PATH"
else
  if [[ -d "$FULL_PATH/manifests" ]]; then
    kubectl -n lab delete -f "$FULL_PATH/manifests" --ignore-not-found=true || true
  fi
  if [[ -d "$FULL_PATH/applicationset" ]]; then
    kubectl -n lab delete -f "$FULL_PATH/applicationset" --ignore-not-found=true || true
  fi
  if [[ -d "$FULL_PATH/overlays/prod" ]]; then
    kubectl -n lab delete -k "$FULL_PATH/overlays/prod" --ignore-not-found=true || true
  fi
fi

# Extra cleanup for cluster-scoped resources if any (VAP in m14)
kubectl delete validatingadmissionpolicy no-latest-tag --ignore-not-found=true 2>/dev/null || true
kubectl delete validatingadmissionpolicy require-tenant-labels --ignore-not-found=true 2>/dev/null || true

# Explicit clean lab just in case
kubectl -n lab delete all --all 2>/dev/null || true

if [[ -f "$FULL_PATH/verify/cleanup.sh" ]]; then
  echo "Running cleanup.sh..."
  bash "$FULL_PATH/verify/cleanup.sh"
fi

exit $VERIFY_EXIT
