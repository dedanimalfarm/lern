#!/usr/bin/env bash
# Проверка решения лабы 08-audit-users
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

REPORT_FILE="/tmp/audit_report.txt"

# 1. Проверяем наличие файла отчета
if [ ! -f "$REPORT_FILE" ]; then
  fail "Файл отчета $REPORT_FILE не найден"
else
  # Загружаем переменные из файла
  SSH_USER=""
  SECRET_MODIFIER_UID=""
  
  # Читаем файл построчно, чтобы безопасно извлечь значения без прямого source
  while IFS= read -r line || [ -n "$line" ]; do
    # Пропускаем пустые строки и комментарии
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    
    if [[ "$line" =~ ^SSH_USER=(.+) ]]; then
      SSH_USER="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^SECRET_MODIFIER_UID=(.+) ]]; then
      SECRET_MODIFIER_UID="${BASH_REMATCH[1]}"
    fi
  done < "$REPORT_FILE"

  # Очищаем от кавычек и лишних пробелов
  SSH_USER=$(echo "$SSH_USER" | tr -d '"'\'' ')
  SECRET_MODIFIER_UID=$(echo "$SECRET_MODIFIER_UID" | tr -d '"'\'' ')

  # 2. Проверяем SSH_USER
  if [ "$SSH_USER" = "hacker" ]; then
    ok "Правильно определен атакующий SSH пользователь: $SSH_USER"
  else
    fail "Неверный или неопределенный SSH_USER в отчете: '$SSH_USER' (ожидалось 'hacker')"
  fi

  # 3. Проверяем SECRET_MODIFIER_UID
  if [ "$SECRET_MODIFIER_UID" = "65534" ]; then
    ok "Правильно определен UID изменившего файл пользователя: $SECRET_MODIFIER_UID"
  else
    fail "Неверный или неопределенный SECRET_MODIFIER_UID в отчете: '$SECRET_MODIFIER_UID' (ожидалось '65534')"
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть невыполненные условия."
  exit 1
fi
