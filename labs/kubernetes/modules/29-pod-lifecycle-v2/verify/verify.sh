#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

# Часть 1: native sidecar — Job завершился (под не завис на вечном sidecar).
require_resource lab job sidecar-job
kubectl -n lab wait --for=condition=complete job/sidecar-job --timeout=120s >/dev/null 2>&1 \
  || fail "job/sidecar-job не завершился (native sidecar?)"
SC=$(kubectl -n lab get job sidecar-job \
  -o jsonpath='{.spec.template.spec.initContainers[0].restartPolicy}' 2>/dev/null || true)
[[ "$SC" == "Always" ]] || fail "sidecar-job: initContainer restartPolicy='$SC', ожидался 'Always' (native sidecar)"
ok "native sidecar: Job Complete, logshipper = init+restartPolicy:Always"

# Часть 2: scheduling gate — под gated-demo держится SchedulingGated.
require_resource lab pod gated-demo
GR=$(kubectl -n lab get pod gated-demo -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || true)
GP=$(kubectl -n lab get pod gated-demo -o jsonpath='{.status.phase}' 2>/dev/null || true)
[[ "$GP" == "Pending" && "$GR" == "SchedulingGated" ]] \
  || fail "gated-demo: phase='$GP' reason='$GR', ожидалось Pending/SchedulingGated"
ok "scheduling gate: gated-demo держится SchedulingGated до снятия gate"

# Часть 3: in-place resize — resize-demo Ready и сконфигурирован под resize.
require_pod_phase lab app=resize-demo Running 2>/dev/null || true
kubectl -n lab wait --for=condition=Ready pod/resize-demo --timeout=60s >/dev/null 2>&1 \
  || fail "resize-demo не Ready"
RP=$(kubectl -n lab get pod resize-demo \
  -o jsonpath='{.spec.containers[0].resizePolicy[0].resourceName}' 2>/dev/null || true)
ALLOC=$(kubectl -n lab get pod resize-demo \
  -o jsonpath='{.status.containerStatuses[0].allocatedResources.cpu}' 2>/dev/null || true)
[[ -n "$RP" && -n "$ALLOC" ]] \
  || fail "resize-demo: resizePolicy='$RP' allocatedResources.cpu='$ALLOC' (in-place resize не доступен?)"
ok "in-place resize: resize-demo Ready, resizePolicy задан, allocatedResources.cpu=$ALLOC"

ok "module 29 verified"
