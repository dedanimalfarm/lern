#!/usr/bin/env bash
set -euo pipefail
for n in $(kubectl get nodes -o jsonpath='{range .items[?(@.spec.unschedulable==true)]}{.metadata.name}{"\n"}{end}'); do
  kubectl uncordon "$n"
done
kubectl -n lab rollout status deploy/drain-demo --timeout=120s
