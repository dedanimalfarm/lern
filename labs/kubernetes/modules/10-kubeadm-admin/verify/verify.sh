#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl

kubectl get nodes >/dev/null || fail "cannot list nodes"

cordoned=$(kubectl get nodes -o jsonpath='{.items[*].spec.unschedulable}')
if [[ "$cordoned" == *"true"* ]]; then
  fail "One or more nodes are still cordoned (SchedulingDisabled). Please run 'kubectl uncordon <node>' to return them to service."
fi

if ! kubectl -n lab get deploy drain-demo >/dev/null 2>&1; then
  fail "Deployment drain-demo not found in namespace lab."
fi

if ! kubectl -n lab get pdb drain-demo-pdb >/dev/null 2>&1; then
  fail "PDB drain-demo-pdb not found in namespace lab."
fi

allowed=$(kubectl -n lab get pdb drain-demo-pdb -o jsonpath='{.status.disruptionsAllowed}')
if [[ "$allowed" -eq 0 ]]; then
  fail "PDB drain-demo-pdb currently blocks drain (ALLOWED DISRUPTIONS is 0). Please scale the deployment to 2 replicas or change PDB maxUnavailable to 1."
fi

ok "module 10 verified"
