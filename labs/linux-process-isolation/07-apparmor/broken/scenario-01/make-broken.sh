#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: профиль загружен в COMPLAIN — неявный запрет
# (/var/log) не блокируется. Host-only: нужен включённый AppArmor.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
[[ -d /sys/kernel/security/apparmor ]] || { echo "AppArmor не активен — сценарий только на реальном хосте"; exit 0; }

MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # каталог 07-apparmor
S=/usr/local/bin/secret-reader.sh
PD=/etc/apparmor.d/usr.local.bin.secret-reader.sh
install -m0755 "$MOD/secret-reader.sh" "$S"
cp "$MOD/profile.aa" "$PD"
apparmor_parser -r "$PD" 2>/dev/null
aa-complain "$S" 2>/dev/null               # БАГ: профиль в complain, не enforce

echo "профиль в COMPLAIN — запись в /var/log НЕ блокируется (только логируется):"
"$S" 2>/dev/null | grep WRITE_VARLOG
echo "(ожидаемо WRITE_VARLOG: OK — complain не энфорсит неявные запреты)"

apparmor_parser -R "$PD" 2>/dev/null; rm -f "$PD" "$S"
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-enforce-mode/fix.sh"
