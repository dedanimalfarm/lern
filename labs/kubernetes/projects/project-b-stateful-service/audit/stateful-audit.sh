#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

echo "==> Запуск аудита stateful-сервиса (Project B)..."

# 1. Проверка Anti-Affinity
AFFINITY=$(kubectl -n lab get sts redis -o jsonpath='{.spec.template.spec.affinity.podAntiAffinity}')
if [[ -n "$AFFINITY" && "$AFFINITY" != "null" ]]; then
  pass "Anti-Affinity настроена для подов Redis"
else
  fail "Anti-Affinity не найдена в StatefulSet"
fi

# 2. Проверка PodDisruptionBudget (PDB)
if kubectl -n lab get pdb redis-pdb >/dev/null 2>&1; then
  MAX_UNAVAILABLE=$(kubectl -n lab get pdb redis-pdb -o jsonpath='{.spec.maxUnavailable}')
  pass "PodDisruptionBudget 'redis-pdb' существует (maxUnavailable: $MAX_UNAVAILABLE)"
else
  fail "PodDisruptionBudget 'redis-pdb' не найден"
fi

# 3. Проверка Backup CronJob
if kubectl -n lab get cronjob redis-backup >/dev/null 2>&1; then
  SCHEDULE=$(kubectl -n lab get cronjob redis-backup -o jsonpath='{.spec.schedule}')
  pass "CronJob 'redis-backup' существует (расписание: $SCHEDULE)"
else
  fail "CronJob 'redis-backup' не найден"
fi

# 4. Проверка Resource Limits
LIMITS=$(kubectl -n lab get sts redis -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}')
if [[ -n "$LIMITS" ]]; then
  pass "Лимиты ресурсов настроены (memory limit: $LIMITS)"
else
  fail "Лимиты ресурсов не настроены для контейнера redis"
fi

echo -e "\n${GREEN}[SUCCESS]${NC} Аудит пройден: stateful-сервис готов к продуктиву (4/4)"
