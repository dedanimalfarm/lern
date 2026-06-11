#!/usr/bin/env bash
# Общие помощники verify-скриптов курса labs/api (по образцу k8s-labs).
# Подключение:  source "$ROOT_DIR/scripts/verify/helpers.sh"
#
# Соглашение: промежуточные require_* при успехе МОЛЧАТ; падение — через
# fail() с понятной причиной. Под set -euo pipefail любые подстановки
# с grep/jq заканчиваются `|| true`, чтобы не убить скрипт до fail().

API="${API:-http://127.0.0.1:8080}"
SINK="${SINK:-http://127.0.0.1:9100}"

ok()   { echo "[OK] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

need_bin() {
  command -v "$1" >/dev/null 2>&1 || fail "не найдена утилита: $1"
}

# Код HTTP-ответа без тела: http_code <curl-аргументы...>
http_code() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" 2>/dev/null || true
}

require_api_up() {
  [[ "$(http_code "$API/health")" == "200" ]] \
    || fail "API не отвечает на $API/health — поднимите стенд: scripts/api.sh up"
}

# require_http <ожидаемый код> <curl-аргументы...>
require_http() {
  local expect="$1" got
  shift
  got="$(http_code "$@")"
  [[ "$got" == "$expect" ]] || fail "ожидался HTTP $expect, получен '$got' ($*)"
}

# require_jq <jq-фильтр> <ожидаемое значение> <curl-аргументы...>
# Сравнивает результат фильтра по телу ответа со строкой.
require_jq() {
  local filter="$1" expect="$2" got
  shift 2
  got="$(curl -s --max-time 10 "$@" 2>/dev/null | jq -r "$filter" 2>/dev/null || true)"
  [[ "$got" == "$expect" ]] \
    || fail "jq '$filter' дал '$got', ожидалось '$expect' ($*)"
}

# require_jq_min <jq-фильтр (число)> <минимум> <curl-аргументы...>
require_jq_min() {
  local filter="$1" min="$2" got
  shift 2
  got="$(curl -s --max-time 10 "$@" 2>/dev/null | jq -r "$filter" 2>/dev/null || true)"
  [[ "$got" =~ ^[0-9]+$ ]] || fail "jq '$filter' дал не число: '$got' ($*)"
  (( got >= min )) || fail "jq '$filter' = $got, ожидалось >= $min ($*)"
}

# Файл существует и является валидным JSON (без внешних зависимостей)
require_valid_json_file() {
  local file="$1"
  [[ -f "$file" ]] || fail "нет файла: $file"
  python3 -m json.tool "$file" >/dev/null 2>&1 \
    || fail "файл не является валидным JSON: $file"
}
