#!/usr/bin/env bash
# verify: грузим enforce-профиль для secret-reader.sh и доказываем, что он
# блокирует root (чтение /etc/passwd, запись /var/log) и пускает разрешённое (/tmp).
# Host-only: без AppArmor в ядре — мягкий пропуск (на WSL2 не падает).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
if [[ ! -d /sys/kernel/security/apparmor ]]; then
  warn "AppArmor не активен в ядре (WSL2/контейнер?) — модуль host-only, проверка пропущена"
  exit 0
fi
need_bin apparmor_parser

MOD="$ROOT_DIR/07-apparmor"
SCRIPT=/usr/local/bin/secret-reader.sh
PROFILE=/etc/apparmor.d/usr.local.bin.secret-reader.sh
require_file "$MOD/secret-reader.sh" "secret-reader.sh"
require_file "$MOD/profile.aa" "profile.aa"

install -m0755 "$MOD/secret-reader.sh" "$SCRIPT"
cp "$MOD/profile.aa" "$PROFILE"
apparmor_parser -r "$PROFILE" 2>/dev/null || fail "профиль не загрузился (apparmor_parser -r)"

OUT=$("$SCRIPT" 2>/dev/null || true)
printf '%s\n' "$OUT" | grep -q 'READ_PASSWD: DENIED' \
  || fail "чтение /etc/passwd НЕ заблокировано (root обошёл MAC?). Вывод: $OUT"
ok "MAC enforce: чтение /etc/passwd запрещено даже root (READ_PASSWD: DENIED)"

printf '%s\n' "$OUT" | grep -q 'WRITE_VARLOG: DENIED' \
  || fail "запись в /var/log НЕ заблокирована. Вывод: $OUT"
ok "запись вне разрешённых путей запрещена (WRITE_VARLOG: DENIED)"

printf '%s\n' "$OUT" | grep -q 'WRITE_TMP: OK' \
  || fail "запись в /tmp должна быть разрешена. Вывод: $OUT"
ok "разрешённая операция работает (WRITE_TMP: OK)"

grep -q secret-reader /sys/kernel/security/apparmor/profiles 2>/dev/null \
  || fail "профиль не виден в /sys/kernel/security/apparmor/profiles"
ok "профиль secret-reader загружен (виден в /sys/kernel/security/apparmor/profiles)"

ok "module 07-apparmor verified"
