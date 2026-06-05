#!/usr/bin/env bash
set -euo pipefail

# 1) find worker nodes
NODE_A=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
NODE_B=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[1].metadata.name}' 2>/dev/null || true)

if [[ -n "$NODE_A" ]]; then
  echo "Preparing node A: $NODE_A"
  kubectl label node "$NODE_A" disktype=ssd --overwrite
fi

if [[ -n "$NODE_B" ]]; then
  echo "Preparing node B: $NODE_B"
  kubectl taint node "$NODE_B" dedicated=lab:NoSchedule --overwrite || true
fi
