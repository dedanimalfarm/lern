#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab
require_deployment_ready lab probe-demo 120s
require_resource lab svc probe-demo
require_service_endpoints lab probe-demo

# Verify init-container completed successfully
if kubectl -n lab get pod init-wait-dns >/dev/null 2>&1; then
  INIT_STATUS=$(kubectl -n lab get pod init-wait-dns -o jsonpath='{.status.initContainerStatuses[0].state.terminated.reason}' 2>/dev/null || true)
  [[ "$INIT_STATUS" == "Completed" ]] || warn "init-container wait-dns did not complete (status: $INIT_STATUS)"
  ok "init-wait-dns pod applied, init-container status: $INIT_STATUS"
else
  warn "init-wait-dns pod is not applied"
fi

# Verify sidecar pod
if kubectl -n lab get pod sidecar-demo >/dev/null 2>&1; then
  RESTART_POLICY=$(kubectl -n lab get pod sidecar-demo -o jsonpath='{.spec.initContainers[0].restartPolicy}' 2>/dev/null || true)
  [[ "$RESTART_POLICY" == "Always" ]] || warn "sidecar-demo does not have restartPolicy: Always on initContainer"
  ok "sidecar-demo pod applied, sidecar restartPolicy: $RESTART_POLICY"
else
  warn "sidecar-demo pod is not applied"
fi

# Verify probe-demo has liveness and readiness probes configured
PROBES=$(kubectl -n lab get deploy probe-demo -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path}' 2>/dev/null || true)
[[ -n "$PROBES" ]] || warn "probe-demo missing livenessProbe"

PROBES=$(kubectl -n lab get deploy probe-demo -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}' 2>/dev/null || true)
[[ -n "$PROBES" ]] || warn "probe-demo missing readinessProbe"

ok "module 02 verified"
