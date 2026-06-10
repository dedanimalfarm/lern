#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

# Части 1–2: бэкенд трейсов и коллектор подняты.
require_deployment_ready lab tempo 180s
require_deployment_ready lab otel-collector 120s

# Часть 3: демо-приложение. Таймаут щедрый: контейнеры ставят зависимости
# pip'ом на старте (~1–3 мин при CPU-лимите 150m), startupProbe это покрывает.
require_deployment_ready lab backend 360s
require_deployment_ready lab frontend 360s

# Сквозной тест пайплайна: запрос через frontend рождает распределённый trace
# (frontend → backend), который должен доехать до Tempo и найтись через search
# API. Запросы к Tempo делаем из пода frontend: busybox-wget там точно есть,
# а Service tempo резолвится.
# Retry-цикл, а не один sleep: на СВЕЖЕразвёрнутом Tempo (QA-прогон с нуля)
# первые спаны становятся searchable не мгновенно (SDK batch ~5s + collector
# batch 2s + livestore ingest).
# ВАЖНО: `|| true` в подстановках обязателен — под set -euo pipefail пустой
# результат grep (exit 1) иначе молча убивает скрипт ДО строки с fail.
TRACE_ID=""
# Окно ~4 мин: при самом первом прогоне после деплоя Tempo индексация может
# занять 1-2+ мин (наблюдалось в QA) — 100с окна давали flaky-FAIL.
for _ in $(seq 1 24); do
  kubectl -n lab exec deploy/frontend -- wget -qO- http://localhost:5000/ >/dev/null 2>&1 || true
  sleep 10
  # TraceQL: {resource.service.name="frontend"} (urlencoded). Легаси-параметр
  # ?tags= в Tempo 3.0 больше не фильтрует — искать нужно через q=<TraceQL>.
  SEARCH=$(kubectl -n lab exec deploy/frontend -- wget -qO- \
    'http://tempo:3200/api/search?q=%7Bresource.service.name%3D%22frontend%22%7D&limit=5' 2>/dev/null || true)
  TRACE_ID=$(printf '%s' "$SEARCH" | grep -o '"traceID":"[0-9a-f]*"' | head -1 | cut -d'"' -f4 || true)
  [[ -n "$TRACE_ID" ]] && break
done
[[ -n "$TRACE_ID" ]] || fail "Tempo search не вернул трейсов frontend за ~4 мин (пайплайн разорван? см. логи otel-collector)"
ok "tempo search: трейс найден (traceID=${TRACE_ID})"

# Найденный трейс может быть от запроса, где спаны backend ещё в полёте —
# поэтому тоже с ретраем добиваемся полного дерева из двух сервисов.
BOTH=""
for _ in $(seq 1 5); do
  TRACE=$(kubectl -n lab exec deploy/frontend -- wget -qO- \
    "http://tempo:3200/api/traces/${TRACE_ID}" 2>/dev/null || true)
  if printf '%s' "$TRACE" | grep -q '"frontend"' && printf '%s' "$TRACE" | grep -q '"backend"'; then
    BOTH=yes; break
  fi
  sleep 10
done
[[ -n "$BOTH" ]] || fail "в трейсе ${TRACE_ID} нет спанов обоих сервисов (traceparent не пробросился?)"
ok "распределённый trace: спаны frontend И backend в одном traceID"

# Часть 4: provisioning-датасорсы Grafana (сам стек 17 для verify не обязателен).
require_resource monitoring secret tempo-datasource
DERIVED=$(kubectl -n monitoring get secret loki-datasource \
  -o jsonpath='{.data.loki-datasource\.yaml}' 2>/dev/null | base64 -d | grep -c derivedFields || true)
[[ "${DERIVED:-0}" -ge 1 ]] || fail "secret loki-datasource без derivedFields (нужен loki-datasource-v2.yaml модуля 30)"
ok "grafana datasources: tempo + loki(derivedFields) на месте"

ok "module 30 verified"
