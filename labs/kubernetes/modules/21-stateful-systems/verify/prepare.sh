#!/usr/bin/env bash
set -euo pipefail

echo "Installing CloudNativePG Operator..."
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.1.yaml

echo "Waiting for CNPG Operator to be ready..."
kubectl wait --for=condition=Available deployment/cnpg-controller-manager -n cnpg-system --timeout=120s

# Give the webhook a few seconds to register
sleep 5
