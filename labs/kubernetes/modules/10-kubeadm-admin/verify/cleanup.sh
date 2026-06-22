#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

info "Cleaning up resources for module 10..."

kubectl -n lab delete deploy drain-demo --ignore-not-found
kubectl -n lab delete pdb drain-demo-pdb --ignore-not-found

# Uncordon all nodes to ensure they are available
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""); do
    if [[ -n "$node" ]]; then
        kubectl uncordon "$node" >/dev/null 2>&1 || true
    fi
done

ok "Cleanup complete"
