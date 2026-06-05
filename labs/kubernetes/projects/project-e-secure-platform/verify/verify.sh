#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"
AUDIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/audit/isolation-audit.sh"

need_bin kubectl
need_bin jq

# Оба тенанта существуют, hardened-приложения развёрнуты (прошли restricted PSA).
for t in tenant-a tenant-b; do
  require_namespace "$t"
  require_deployment_ready "$t" web 120s
  ok "$t: hardened web развёрнут (прошёл restricted PSA)"
done

# policy-as-code на месте.
require_resource "" validatingadmissionpolicy tenant-no-latest-tag 2>/dev/null \
  || kubectl get validatingadmissionpolicy tenant-no-latest-tag >/dev/null 2>&1 \
  || fail "VAP tenant-no-latest-tag отсутствует"
ok "VAP tenant-no-latest-tag присутствует"

# Делегируем полный аудит изоляции (6 контролей) каждому тенанту.
for t in tenant-a tenant-b; do
  bash "$AUDIT" "$t" >/dev/null 2>&1 || fail "isolation-audit провалился для $t (запусти: bash audit/isolation-audit.sh $t)"
  ok "isolation-audit пройден для $t (6/6 контролей)"
done

ok "project-e secure-platform verified"
