#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
kubectl -n lab get deploy drain-demo >/dev/null 2>&1 || kubectl apply -f "$DIR/broken/scenario-01/deploy.yaml" >/dev/null
for n in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  if ! kubectl get node "$n" -o jsonpath='{.spec.taints[*].key}' | grep -q control-plane; then
    kubectl cordon "$n" >/dev/null
  fi
done
kubectl -n lab scale deploy drain-demo --replicas=3 >/dev/null
echo "инцидент применён: масштабируйте/смотрите kubectl -n lab get pods -l app=drain-demo"
