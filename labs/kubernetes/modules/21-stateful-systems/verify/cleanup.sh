#!/usr/bin/env bash
set -euo pipefail

echo "Removing CloudNativePG Operator..."
kubectl delete -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.1.yaml --ignore-not-found || true
