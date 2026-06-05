#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/root/.kube/kubespray.conf}"

echo "Uninstalling Argo Rollouts..."
kubectl delete -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml --ignore-not-found=true
kubectl delete namespace argo-rollouts --ignore-not-found=true
