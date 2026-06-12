#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

require_deployment_ready lab loki 120s
require_deployment_ready lab payment-api 120s
kubectl -n lab rollout status daemonset/promtail --timeout=120s >/dev/null

# Живость API — необходимое, но НЕ достаточное условие (грабля из CLAUDE.md:
# «живость бэкенда не доказывает доставку») — поэтому ниже проверяем конвейер.
kubectl -n lab exec deploy/loki -- wget -qO- http://localhost:3100/loki/api/v1/status/buildinfo >/dev/null 2>&1 \
  || fail "loki API не отвечает"
ok "loki is ready"

# Запросы заранее URL-encoded (без зависимости от python в окружении verify):
# Q1: {app="payment-api"} | json | __error__="" | status >= 500
#     — доказывает доставку, работу cri-stage И json-парсера разом.
Q1='%7Bapp%3D%22payment-api%22%7D%20%7C%20json%20%7C%20__error__%3D%22%22%20%7C%20status%20%3E%3D%20500'
# Q2: sum(rate({namespace="lab"}[1m])) — метрики-из-логов считаются.
Q2='sum%28rate%28%7Bnamespace%3D%22lab%22%7D%5B1m%5D%29%29'

# Доставка асинхронна (генератор пишет ~1.4 строк/с, ~15% из них 500-е;
# promtail батчит). На холодном старте promtail заново шлёт логи ВСЕГО
# кластера (positions в emptyDir) — свежие строки ждут очередь, поэтому
# окно щедрое, ~4 минуты.
DELIVERED=""
for _ in $(seq 1 48); do
  RES=$(kubectl -n lab exec deploy/loki -- wget -qO- \
    "http://localhost:3100/loki/api/v1/query_range?query=${Q1}&limit=1&since=5m" 2>/dev/null || true)
  # Матчим по метке парсера в stream ("status":"500" — значение в кавычках!);
  # тело лога в values экранировано (\"status\":500) и для grep ненадёжно.
  if printf '%s' "$RES" | grep -q '"status":"500"'; then DELIVERED=yes; break; fi
  sleep 5
done
[[ -n "$DELIVERED" ]] || fail "строки payment-api со status=500 не нашлись в Loki за ~4 мин (конвейер promtail->loki или cri-stage сломан; смотри 429 в логах promtail)"
ok "логи доставляются, cri-stage и json-парсер работают (status>=500 находятся)"

METRIC=$(kubectl -n lab exec deploy/loki -- wget -qO- \
  "http://localhost:3100/loki/api/v1/query?query=${Q2}" 2>/dev/null || true)
RATE=$(printf '%s' "$METRIC" | grep -o '"value":\[[^]]*\]' | head -1 | grep -o '"[0-9.]*"' | tr -d '"' || true)
awk -v r="${RATE:-0}" 'BEGIN{exit !(r>0)}' || fail "метрик-запрос rate() по логам вернул 0/пусто"
ok "метрики из логов: rate() = ${RATE} строк/с"

ok "module 18 verified"
