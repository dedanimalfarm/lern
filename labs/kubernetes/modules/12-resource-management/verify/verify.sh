#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

# Часть 1: три пода получили ПРАВИЛЬНЫЙ QoS-класс по своим requests/limits.
check_qos() {
  local pod="$1" want="$2" got
  require_resource lab pod "$pod"
  got=$(kubectl -n lab get pod "$pod" -o jsonpath='{.status.qosClass}' 2>/dev/null || true)
  [[ "$got" == "$want" ]] || fail "pod/$pod qosClass='$got', expected '$want'"
}
check_qos qos-guaranteed Guaranteed
check_qos qos-burstable  Burstable
check_qos qos-besteffort BestEffort
ok "QoS classes assigned correctly (Guaranteed/Burstable/BestEffort)"

# Часть 2: PriorityClass'ы созданы (cluster-scoped) с ожидаемыми value.
for pc in lab-low:100 lab-high:1000; do
  name="${pc%%:*}"; val="${pc##*:}"
  got=$(kubectl get priorityclass "$name" -o jsonpath='{.value}' 2>/dev/null || true)
  [[ "$got" == "$val" ]] || fail "priorityclass/$name value='$got', expected '$val'"
done
ok "PriorityClass lab-low(100) + lab-high(1000) present"

ok "module 12 verified"
