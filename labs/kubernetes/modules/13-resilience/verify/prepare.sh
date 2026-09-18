#!/usr/bin/env bash
set -euo pipefail

kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab >/dev/null
kubectl -n lab get quota lab-quota >/dev/null 2>&1 || echo "prepare: нет ResourceQuota lab-quota — выполните bash scripts/bootstrap/01-apply-quotas.sh"
W=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers 2>/dev/null | wc -l)
[[ "$W" -ge 2 ]] || echo "prepare: воркеров меньше двух ($W) — topologySpread и anti-affinity не покажут распределение"
for n in $(kubectl get nodes -o jsonpath='{.items[?(@.spec.unschedulable==true)].metadata.name}'); do kubectl uncordon "$n"; done
echo "prepare: воркеров: $W"
