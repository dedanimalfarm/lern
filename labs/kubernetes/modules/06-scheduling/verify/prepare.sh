#!/usr/bin/env bash
set -euo pipefail

# 1) find a worker node
NODE_A=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || kubectl get nodes -o jsonpath='{.items[1].metadata.name}')

if [[ -n "$NODE_A" ]]; then
  echo "Preparing node: $NODE_A"
  kubectl label node "$NODE_A" disktype=ssd --overwrite
  kubectl taint node "$NODE_A" special=true:NoSchedule --overwrite || true
else
  echo "No suitable node found for preparation."
fi
