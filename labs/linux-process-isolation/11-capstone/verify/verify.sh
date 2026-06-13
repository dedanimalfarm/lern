#!/usr/bin/env bash
# verify: запускаем mycontainer и проверяем интеграцию всех примитивов —
# изоляции (PID/UTS/UID/overlay), малое число процессов, закрытый побег
# /proc/1/root (pivot_root), и чистую уборку после контейнера.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
MYC="$ROOT_DIR/11-capstone/mycontainer.sh"
require_file "$MYC" "mycontainer.sh"

# Один запуск контейнера собирает все маркеры. ESCAPE=ID дистрибутива из корня,
# куда ведёт /proc/1/root: alpine ⇒ побег внутри контейнера; ubuntu/debian ⇒ утёк на хост.
# shellcheck disable=SC2016  # $(...) раскрывается во ВНУТРЕННЕМ sh контейнера, не здесь
OUT=$("$MYC" run -m 64M alpine -- sh -c 'echo "PID1=$(cat /proc/1/comm)"; echo "HOST=$(hostname)"; echo "UID=$(id -u)"; echo "OS=$(grep ^ID= /etc/os-release | cut -d= -f2)"; echo "PROCS=$(ls -d /proc/[0-9]* 2>/dev/null | wc -l)"; echo "ESCAPE=$(chroot /proc/1/root /bin/sh -c "grep ^ID= /etc/os-release | cut -d= -f2" 2>/dev/null || echo fail)"' 2>&1 || true)

printf '%s\n' "$OUT" | grep -q '^PID1=sh'           || fail "PID 1 != sh. Вывод: $OUT"
printf '%s\n' "$OUT" | grep -q '^HOST=mycontainer'  || fail "hostname != mycontainer. Вывод: $OUT"
printf '%s\n' "$OUT" | grep -q '^UID=0'             || fail "uid != 0. Вывод: $OUT"
printf '%s\n' "$OUT" | grep -q '^OS=alpine'         || fail "os != alpine (overlay не сработал). Вывод: $OUT"
ok "контейнер запущен: PID 1=sh, hostname=mycontainer, uid=0, os=alpine"

P=$(printf '%s\n' "$OUT" | sed -n 's/^PROCS=//p' | tr -d ' ' || true)
[[ -n "$P" && "$P" -le 6 ]] || fail "слишком много процессов в контейнере (PROCS='$P'). Вывод: $OUT"
ok "PID-ns изолирован: внутри мало процессов ($P)"

ESC=$(printf '%s\n' "$OUT" | sed -n 's/^ESCAPE=//p' | tr -d ' ' || true)
[[ "$ESC" == "alpine" ]] \
  || fail "побег /proc/1/root НЕ закрыт (escape='$ESC', ожидался alpine = корень контейнера). Вывод: $OUT"
ok "pivot_root закрыл побег: /proc/1/root → корень контейнера (alpine), не хост"

# уборка mycontainer должна быть чистой
sleep 1
if mount 2>/dev/null | grep -q /var/lib/mycontainer; then fail "остался overlay-mount от mycontainer"; fi
if ls -d /sys/fs/cgroup/mycontainer-* >/dev/null 2>&1; then fail "остались cgroup mycontainer-*"; fi
ok "уборка чистая: нет overlay-mount и cgroup mycontainer-*"

ok "module 11-capstone verified"
