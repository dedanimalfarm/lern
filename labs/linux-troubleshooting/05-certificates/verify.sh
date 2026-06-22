#!/usr/bin/env bash
# Проверка решения лабы 05-certificates
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

# 1. Проверяем наличие созданных файлов
if [ ! -f /tmp/certs/valid.crt ] || [ ! -f /tmp/certs/valid.key ]; then
  fail "Результирующие файлы /tmp/certs/valid.crt или /tmp/certs/valid.key не найдены"
else
  ok "Файлы valid.crt и valid.key созданы"
  
  # 2. Проверяем валидность сертификата (не просрочен ли)
  if ! openssl x509 -checkend 86400 -noout -in /tmp/certs/valid.crt >/dev/null 2>&1; then
    fail "Выбранный сертификат valid.crt просрочен или невалиден"
  else
    ok "Сертификат valid.crt действителен"
  fi
  
  # 3. Проверяем соответствие ключа сертификату через хэш модуля
  mod_cert=$(openssl x509 -noout -modulus -in /tmp/certs/valid.crt 2>/dev/null | openssl md5 2>/dev/null)
  mod_key=$(openssl rsa -noout -modulus -in /tmp/certs/valid.key 2>/dev/null | openssl md5 2>/dev/null)
  
  if [ -z "$mod_cert" ] || [ -z "$mod_key" ] || [ "$mod_cert" != "$mod_key" ]; then
    fail "Приватный ключ valid.key не соответствует сертификату valid.crt"
  else
    ok "Приватный ключ соответствует сертификату (modulus совпадает)"
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
