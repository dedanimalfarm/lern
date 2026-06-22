#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

echo "Checking if CloudNativePG CRDs are registered..."
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || { echo "CRD clusters.postgresql.cnpg.io not found"; exit 1; }
kubectl get crd scheduledbackups.postgresql.cnpg.io >/dev/null 2>&1 || { echo "CRD scheduledbackups.postgresql.cnpg.io not found"; exit 1; }

echo "Checking if PostgreSQL cluster is Ready..."
kubectl -n lab wait --for=condition=Ready cluster/my-db --timeout=400s

echo "Checking if db-client app is ready..."
require_deployment_ready lab db-client 60s

echo "Checking for ScheduledBackup..."
if ! kubectl -n lab get scheduledbackup my-db-backup >/dev/null 2>&1; then
  echo "ScheduledBackup my-db-backup not found"
  exit 1
fi

echo "Checking PostgreSQL pods..."
PRIMARY=$(kubectl -n lab get cluster my-db -o=jsonpath='{.status.currentPrimary}' 2>/dev/null || echo "")
if [[ -z "$PRIMARY" ]]; then
  echo "Primary pod not found in cluster status"
  exit 1
fi
echo "Primary pod: $PRIMARY"

ok "module 21 verified"
