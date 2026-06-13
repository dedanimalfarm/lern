#!/usr/bin/env bash
# Управление учебным стендом курса labs/api.
#
#   scripts/api.sh up         поднять Helpdesk API (порт $PORT, default 8080)
#   scripts/api.sh down       погасить Helpdesk API
#   scripts/api.sh status     здоровье + текущая конфигурация стенда
#   scripts/api.sh logs [N]   последние N строк лога (default 20)
#   scripts/api.sh sink-up    поднять приёмник вебхуков (порт 9100)
#   scripts/api.sh sink-down  погасить приёмник вебхуков
#   scripts/api.sh tls-up     поднять стенд по HTTPS (порт 8443, самоподпись)
#   scripts/api.sh tls-down   погасить HTTPS-стенд
#
# Конфигурация сервера передаётся переменными окружения при `up`:
#   AUTH_MODE=token RATE_LIMIT=5 scripts/api.sh up
# Поддерживаются: PORT, AUTH_MODE, API_KEY, TOKEN_SECRET, TOKEN_TTL,
#                 RATE_LIMIT, FAULT, WEBHOOK_URL, CORS_ORIGIN, TLS_CERT,
#                 TLS_KEY (см. helpdesk_api.py).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$ROOT_DIR/common/server/helpdesk_api.py"
SINK="$ROOT_DIR/common/server/webhook_sink.py"
RUN_DIR="${TMPDIR:-/tmp}/api-lab"
API_PORT="${PORT:-8080}"
SINK_PORT="${SINK_PORT:-9100}"

mkdir -p "$RUN_DIR"

wait_health() { # url, попыток (по 0.5 с)
  local url="$1" tries="${2:-20}" i insecure=()
  # Для HTTPS-стенда сертификат самоподписанный — health-пробу пускаем с -k.
  # Недоверие к этому серту разбирается в модуле 08 как учебная цель.
  [[ "$url" == https://* ]] && insecure=(-k)
  for ((i = 0; i < tries; i++)); do
    if curl -s "${insecure[@]}" -o /dev/null --max-time 2 "$url"; then
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

stop_by_pidfile() { # pidfile
  # Гасим ТОЛЬКО процесс из pidfile, без pkill по паттерну. Нужно для
  # HTTPS-стенда: его argv (python3 helpdesk_api.py) совпадает с основным
  # HTTP-стендом, поэтому pkill -f "helpdesk_api.py" убил бы и сервер на
  # :8080. По pid коллизии нет.
  local pidfile="$1"
  if [[ -f "$pidfile" ]]; then
    kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
  fi
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
  tls-up)
    # Самоподписанный сертификат для модуля про TLS: генерим один раз,
    # CN=localhost. Браузер/curl без -k его НЕ доверяют — это и есть
    # учебная цель (увидеть ошибку доверия и научиться её читать).
    TLS_PORT="${TLS_PORT:-8443}"
    CERT="$RUN_DIR/lab-cert.pem"
    KEY="$RUN_DIR/lab-key.pem"
    if [[ ! -f "$CERT" || ! -f "$KEY" ]]; then
      openssl req -x509 -newkey rsa:2048 -nodes -keyout "$KEY" -out "$CERT" \
        -days 365 -subj "/CN=localhost" >/dev/null 2>&1 \
        || { echo "[FAIL] нет openssl — поставьте его для tls-up" >&2; exit 1; }
    fi
    stop_by_pidfile "$RUN_DIR/tls.pid"
    PORT="$TLS_PORT" TLS_CERT="$CERT" TLS_KEY="$KEY" \
      nohup python3 "$SERVER" >"$RUN_DIR/helpdesk-tls.log" 2>&1 &
    echo $! >"$RUN_DIR/tls.pid"
    # -k: health-проверку делаем сами, доверие к самоподписи — урок модуля
    wait_health "https://127.0.0.1:${TLS_PORT}/health" \
      || { echo "[FAIL] HTTPS-стенд не поднялся: $RUN_DIR/helpdesk-tls.log" >&2; exit 1; }
    echo "[OK] helpdesk-api по HTTPS на https://127.0.0.1:${TLS_PORT} (самоподпись; cert: $CERT)"
    ;;
  tls-down)
    stop_by_pidfile "$RUN_DIR/tls.pid"
    echo "[OK] HTTPS-стенд остановлен"
    ;;
  *)
    grep '^#   ' "$0" | sed 's/^#   //'
    exit 1
    ;;
esac
