#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab
require_deployment_ready lab resilient-app 180s
require_resource lab pdb resilient-app-pdb

NODES=$(kubectl -n lab get pods -l app=resilient-app -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | grep -c . || true)
WORKERS=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers 2>/dev/null | wc -l || true)
if [[ "${WORKERS:-0}" -ge 2 ]]; then
  [[ "${NODES:-0}" -ge 2 ]] || fail "topologySpread: воркеров $WORKERS, а все реплики resilient-app на одной ноде"
  ok "topologySpread: реплики на $NODES нодах из $WORKERS воркеров"
else
  warn "воркеров меньше двух ($WORKERS) — распределение по нодам не проверить"
fi

ALLOWED=$(kubectl -n lab get pdb resilient-app-pdb -o jsonpath='{.status.disruptionsAllowed}' 2>/dev/null || true)
[[ "$ALLOWED" == "1" ]] || fail "PDB minAvailable=2 при 3 Ready-репликах должен разрешать ровно 1 disruption, сейчас '${ALLOWED:-?}'"

evict() {
  kubectl create --raw "/api/v1/namespaces/lab/pods/$1/eviction" -f - 2>&1 <<EOF || true
{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"$1","namespace":"lab"}}
EOF
}
mapfile -t PODS < <(kubectl -n lab get pods -l app=resilient-app --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
[[ ${#PODS[@]} -ge 3 ]] || fail "ожидали 3 Running-реплики resilient-app, есть ${#PODS[@]}"
R1=$(evict "${PODS[0]}")
R2=$(evict "${PODS[1]}")
[[ "$R1" != *"disruption budget"* ]] || fail "первое выселение должно пройти (allowed=1), а PDB его отклонил: $R1"
[[ "$R2" == *"disruption budget"* ]] || fail "второе выселение подряд должно быть отклонено PDB (minAvailable=2), а прошло: ${R2:0:120}"
ok "PDB: первое выселение через Eviction API прошло, второе отклонено — «Cannot evict pod as it would violate the pod's disruption budget»"

require_deployment_ready lab resilient-app 180s
ok "после выселения Deployment вернулся к 3/3"

ok "module 13 verified"
