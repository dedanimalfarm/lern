#!/usr/bin/env bash
set -euo pipefail

echo "Removing lab namespace and all its resources..."
# We delete the resources directly to avoid getting stuck if operator is deleted first
kubectl delete -n lab cluster my-db --timeout=60s --ignore-not-found || true
kubectl delete -n lab scheduledbackup my-db-backup --timeout=60s --ignore-not-found || true
kubectl delete -n lab deployment db-client --ignore-not-found || true

kubectl delete namespace lab --timeout=120s --ignore-not-found || true

echo "Removing CloudNativePG Operator and its CRDs/Webhooks..."
kubectl delete -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.1.yaml --ignore-not-found || true

echo "Cleanup complete."
