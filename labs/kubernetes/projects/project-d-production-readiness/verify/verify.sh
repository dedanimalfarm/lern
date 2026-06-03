#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"
PROJ="$ROOT_DIR/projects/project-d-production-readiness"

need_bin kubectl
need_bin jq
require_namespace lab
require_deployment_ready lab shop 120s

# Гейт прод-готовности: аудит должен пройти БЕЗ провалов (exit 0).
if bash "$PROJ/audit/audit.sh" lab shop; then
  ok "production-readiness audit: 0 провалов (все 11 критериев)"
else
  fail "production-readiness audit обнаружил невыполненные критерии (см. вывод выше)"
fi

ok "project-d verified"
