#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/root/.kube/kubespray.conf}"

# Версия запинована (releases/latest ломает воспроизводимость лабы и может
# молча сменить поведение CRD между прогонами).
ROLLOUTS_VERSION="v1.9.0"
BASE_URL="https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}"

echo "Installing Argo Rollouts ${ROLLOUTS_VERSION}..."
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts -f "${BASE_URL}/install.yaml"

echo "Waiting for Argo Rollouts controller..."
kubectl wait --for=condition=Available deployment/argo-rollouts -n argo-rollouts --timeout=180s

if ! kubectl argo rollouts version >/dev/null 2>&1; then
  echo "Installing Argo Rollouts kubectl plugin ${ROLLOUTS_VERSION}..."
  curl -sLo /tmp/kubectl-argo-rollouts "${BASE_URL}/kubectl-argo-rollouts-linux-amd64"
  chmod +x /tmp/kubectl-argo-rollouts
  sudo mv /tmp/kubectl-argo-rollouts /usr/local/bin/kubectl-argo-rollouts
fi
