#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

echo "Deleting CRD..."
kubectl delete -f "$ROOT_DIR/modules/19-crd-operators/manifests/crd.yaml" --ignore-not-found=true
