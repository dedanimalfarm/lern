#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/root/.kube/kubespray.conf}"

ROLLOUTS_VERSION="v1.9.0"

echo "Uninstalling Argo Rollouts ${ROLLOUTS_VERSION}..."
kubectl delete -n argo-rollouts \
  -f "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/install.yaml" \
  --ignore-not-found=true 2>/dev/null || true
kubectl delete namespace argo-rollouts --ignore-not-found=true
