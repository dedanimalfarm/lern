#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

echo "Applying CRD..."
kubectl apply -f "$ROOT_DIR/modules/19-crd-operators/manifests/crd.yaml"

echo "Waiting for CRD to be established..."
kubectl wait --for condition=established --timeout=60s crd/webapps.lab.example.com
