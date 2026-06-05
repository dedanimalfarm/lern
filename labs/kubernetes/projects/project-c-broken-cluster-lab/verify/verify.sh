#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

PROJ="$ROOT_DIR/projects/project-c-broken-cluster-lab"

# Verify solutions exist in repository (базовые 4 + новые инциденты capstone F)
for s in crashloop-fixed.yaml readiness-fixed.yaml imagepullbackoff-fixed.yaml oomkilled-fixed.yaml \
         dns-failure-fixed.yaml scheduling-pending-fixed.yaml sync-fail-fixed.yaml cert-expiry-fixed.sh; do
  [[ -f "$PROJ/solutions/$s" ]] || fail "missing solution: $s"
done
ok "все 8 solution-файлов на месте (4 базовых + 4 новых)"

# Verify новые broken-сценарии и триаж-инструмент присутствуют
for b in dns-failure.yaml scheduling-pending.yaml sync-fail.yaml cert-expiry/setup.sh; do
  [[ -f "$PROJ/broken/$b" ]] || fail "missing broken scenario: $b"
done
[[ -x "$PROJ/triage/incident-triage.sh" || -f "$PROJ/triage/incident-triage.sh" ]] || fail "missing triage tool"
ok "новые сценарии (dns/scheduling/sync/cert) + триаж-инструмент на месте"

# Verify broken pods are in expected failure states (if deployed)
check_broken_pod() {
  local pod="$1"
  local expected="$2"
  if kubectl -n lab get pod "$pod" >/dev/null 2>&1; then
    # Check waiting reason
    local reason
    reason=$(kubectl -n lab get pod "$pod" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)
    if [[ "$reason" == "$expected" ]]; then
      ok "broken pod $pod is in expected state: $expected"
      return 0
    fi
    # Check last terminated reason
    reason=$(kubectl -n lab get pod "$pod" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null || true)
    if [[ "$reason" == "$expected" ]]; then
      ok "broken pod $pod has lastState: $expected"
      return 0
    fi
    warn "broken pod $pod present but state='$reason', expected='$expected'"
  else
    warn "broken pod $pod not deployed yet (expected — deploy it to test troubleshooting)"
  fi
}

check_broken_pod "crashloop-app"     "CrashLoopBackOff"
check_broken_pod "imagepull-app"     "ImagePullBackOff"
check_broken_pod "oom-app"           "OOMKilled"

ok "project C verify script executed"
