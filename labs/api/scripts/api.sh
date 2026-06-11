#!/usr/bin/env bash
# Управление учебным стендом курса labs/api.
#
#   scripts/api.sh up         поднять Helpdesk API (порт $PORT, default 8080)
#   scripts/api.sh down       погасить Helpdesk API
#   scripts/api.sh status     здоровье + текущая конфигурация стенда
#   scripts/api.sh logs [N]   последние N строк лога (default 20)
#   scripts/api.sh sink-up    поднять приёмник вебхуков (порт 9100)
#   scripts/api.sh sink-down  погасить приёмник вебхуков
#
# Конфигурация сервера передаётся переменными окружения при `up`:
#   AUTH_MODE=token RATE_LIMIT=5 scripts/api.sh up
# Поддерживаются: PORT, AUTH_MODE, API_KEY, TOKEN_SECRET, TOKEN_TTL,
#                 RATE_LIMIT, FAULT, WEBHOOK_URL (см. helpdesk_api.py).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$ROOT_DIR/common/server/helpdesk_api.py"
SINK="$ROOT_DIR/common/server/webhook_sink.py"
RUN_DIR="${TMPDIR:-/tmp}/api-lab"
API_PORT="${PORT:-8080}"
SINK_PORT="${SINK_PORT:-9100}"

mkdir -p "$RUN_DIR"

wait_health() { # url, попыток (по 0.5 с)
  local url="$1" tries="${2:-20}" i
  for ((i = 0; i < tries; i++)); do
    if curl -s -o /dev/null --max-time 2 "$url"; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

stop_by_pattern() { # pidfile, pattern
  local pidfile="$1" pattern="$2"
  if [[ -f "$pidfile" ]]; then
    kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
  fi
  # подстраховка: процесс мог быть запущен мимо api.sh
  pkill -f "$pattern" 2>/dev/null || true
}

case "${1:-}" in
  up)
    stop_by_pattern "$RUN_DIR/api.pid" "helpdesk_api.py"
    nohup python3 "$SERVER" >"$RUN_DIR/helpdesk-api.log" 2>&1 &
    echo $! >"$RUN_DIR/api.pid"
    wait_health "http://127.0.0.1:${API_PORT}/health" \
      || { echo "[FAIL] API не поднялся, смотрите: $0 logs" >&2; exit 1; }
    echo "[OK] helpdesk-api на http://127.0.0.1:${API_PORT} (лог: $RUN_DIR/helpdesk-api.log)"
    head -1 "$RUN_DIR/helpdesk-api.log"
    ;;
  down)
    stop_by_pattern "$RUN_DIR/api.pid" "helpdesk_api.py"
    echo "[OK] helpdesk-api остановлен"
    ;;
  status)
    curl -s --max-time 2 "http://127.0.0.1:${API_PORT}/health" \
      || { echo "[FAIL] API не отвечает на :${API_PORT}" >&2; exit 1; }
    echo
    curl -s "http://127.0.0.1:${API_PORT}/api/v1/_lab/state"
    echo
    ;;
  logs)
    tail -n "${2:-20}" "$RUN_DIR/helpdesk-api.log"
    ;;
  sink-up)
    stop_by_pattern "$RUN_DIR/sink.pid" "webhook_sink.py"
    PORT="$SINK_PORT" nohup python3 "$SINK" >"$RUN_DIR/webhook-sink.log" 2>&1 &
    echo $! >"$RUN_DIR/sink.pid"
    wait_health "http://127.0.0.1:${SINK_PORT}/health" \
      || { echo "[FAIL] sink не поднялся: $RUN_DIR/webhook-sink.log" >&2; exit 1; }
    echo "[OK] webhook-sink на http://127.0.0.1:${SINK_PORT} (лог: $RUN_DIR/webhook-sink.log)"
    ;;
  sink-down)
    stop_by_pattern "$RUN_DIR/sink.pid" "webhook_sink.py"
    echo "[OK] webhook-sink остановлен"
    ;;
  *)
    grep '^#   ' "$0" | sed 's/^#   //'
    exit 1
    ;;
esac
