#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

echo "Cleaning up module 29..."

kubectl -n lab delete job sidecar-job --ignore-not-found
kubectl -n lab delete pod gated-demo resize-demo --ignore-not-found

echo "[OK] Cleanup complete."
