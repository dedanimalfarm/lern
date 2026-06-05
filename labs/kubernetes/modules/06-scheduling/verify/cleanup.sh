#!/usr/bin/env bash
set -euo pipefail

# Remove label and taint from all nodes to be safe
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  kubectl label node "$node" disktype- 2>/dev/null || true
  kubectl taint node "$node" dedicated=lab:NoSchedule- 2>/dev/null || true
  kubectl taint node "$node" special=true:NoSchedule- 2>/dev/null || true
done
