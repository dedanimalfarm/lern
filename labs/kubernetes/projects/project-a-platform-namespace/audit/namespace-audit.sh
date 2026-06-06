#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

echo "==> Запуск аудита namespace 'platform' (Project A)..."

# 1. Проверка Default Deny NetworkPolicy
if kubectl -n platform get networkpolicy default-deny -o yaml | grep -q "podSelector: {}"; then
  pass "Default Deny NetworkPolicy активна"
else
  fail "Default Deny NetworkPolicy не найдена или не имеет пустого podSelector"
fi

# 2. Проверка PodSecurityAdmission (Policy)
PSA_ENFORCE=$(kubectl get ns platform -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')
if [[ "$PSA_ENFORCE" == "restricted" ]]; then
  pass "PSA policy 'restricted' применена к namespace"
else
  fail "PSA policy 'restricted' не применена. Текущее значение: $PSA_ENFORCE"
fi

# 3. Проверка ResourceQuota
if kubectl -n platform get resourcequota platform-quota >/dev/null 2>&1; then
  pass "ResourceQuota 'platform-quota' существует"
else
  fail "ResourceQuota 'platform-quota' не найдена"
fi

# 4. Проверка LimitRange
if kubectl -n platform get limitrange platform-limits >/dev/null 2>&1; then
  pass "LimitRange 'platform-limits' существует"
else
  fail "LimitRange 'platform-limits' не найдена"
fi

echo -e "\n${GREEN}[SUCCESS]${NC} Аудит пройден: namespace platform готов к продуктиву (4/4)"
