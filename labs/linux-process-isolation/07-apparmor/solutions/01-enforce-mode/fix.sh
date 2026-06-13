#!/usr/bin/env bash
# Чинит инцидент scenario-01: переводим профиль в enforce — неявные запреты снова
# блокируются. Host-only: нужен включённый AppArmor.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
[[ -d /sys/kernel/security/apparmor ]] || { echo "AppArmor не активен — только на реальном хосте"; exit 0; }

MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # каталог 07-apparmor
S=/usr/local/bin/secret-reader.sh
PD=/etc/apparmor.d/usr.local.bin.secret-reader.sh
install -m0755 "$MOD/secret-reader.sh" "$S"
cp "$MOD/profile.aa" "$PD"
apparmor_parser -r "$PD" 2>/dev/null
aa-enforce "$S" 2>/dev/null                # фикс: enforce

echo "профиль в ENFORCE — запись в /var/log заблокирована:"
"$S" 2>/dev/null | grep WRITE_VARLOG
echo "(WRITE_VARLOG: DENIED — enforce блокирует неявные запреты)"

apparmor_parser -R "$PD" 2>/dev/null; rm -f "$PD" "$S"
