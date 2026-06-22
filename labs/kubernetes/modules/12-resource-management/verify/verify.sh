#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
if [ -f "$ROOT_DIR/scripts/verify/helpers.sh" ]; then
  source "$ROOT_DIR/scripts/verify/helpers.sh"
fi

if ! type fail >/dev/null 2>&1; then
  fail() { echo -e "❌ [FAIL] $*"; exit 1; }
  ok() { echo -e "✅ [OK] $*"; }
  require_namespace() { kubectl get ns "$1" >/dev/null 2>&1 || fail "namespace $1 missing"; }
  require_resource() { kubectl -n "$1" get "$2" "$3" >/dev/null 2>&1 || fail "$2 $3 in ns $1 missing"; }
fi

if ! command -v kubectl >/dev/null 2>&1; then
    fail "kubectl is required"
fi

require_namespace lab

# Часть 1: три пода получили ПРАВИЛЬНЫЙ QoS-класс
check_qos() {
  local pod="$1" want="$2" got
  require_resource lab pod "$pod"
  got=$(kubectl -n lab get pod "$pod" -o jsonpath='{.status.qosClass}' 2>/dev/null || true)
  [[ "$got" == "$want" ]] || fail "pod/$pod qosClass='$got', expected '$want'"
}

check_qos qos-guaranteed Guaranteed
check_qos qos-burstable Burstable
check_qos qos-besteffort BestEffort
ok "QoS classes assigned correctly"

# Часть 2: PriorityClass'ы
for pc in lab-low:100 lab-high:1000; do
  name="${pc%%:*}"; val="${pc##*:}"
  got=$(kubectl get priorityclass "$name" -o jsonpath='{.value}' 2>/dev/null || true)
  [[ "$got" == "$val" ]] || fail "priorityclass/$name value='$got', expected '$val'"
done
ok "PriorityClasses verified"

# Проверка OOM решения, если под mem-hog запущен
if kubectl -n lab get pod mem-hog >/dev/null 2>&1; then
    limit=$(kubectl -n lab get pod mem-hog -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null || true)
    if [[ "$limit" != "256Mi" ]]; then
        fail "mem-hog limits.memory is $limit, expected 256Mi (fix OOM)"
    else
        ok "mem-hog limits.memory correctly fixed to 256Mi"
    fi
fi

ok "Module 12 verified"
