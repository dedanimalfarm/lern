#!/usr/bin/env bash
set -euo pipefail

kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab >/dev/null
kubectl -n lab get quota lab-quota >/dev/null 2>&1 || echo "prepare: нет ResourceQuota lab-quota — выполните bash scripts/bootstrap/01-apply-quotas.sh"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for n in $(kubectl get nodes -o jsonpath='{.items[?(@.spec.unschedulable==true)].metadata.name}'); do kubectl uncordon "$n"; done
kubectl apply -f "$DIR/../broken/scenario-01/deploy.yaml" -f "$DIR/../solutions/01-drain-blocked/pdb.yaml"
kubectl -n lab scale deploy drain-demo --replicas=2
kubectl -n lab rollout status deploy/drain-demo --timeout=120s
echo "prepare: drain-demo (2 реплики) + PDB drain-demo-pdb готовы, ноды uncordoned"
