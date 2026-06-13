#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: не-root ставит seccomp-фильтр без
# PR_SET_NO_NEW_PRIVS → prctl(PR_SET_SECCOMP) падает с EACCES (errno 13).
# Скрипт копируем в /tmp, т.к. nobody не читает каталог под /root.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
command -v python3 >/dev/null || { echo "нет python3 — sudo ./00-setup/install.sh"; exit 1; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$DIR/seccomp_no_nnp.py" /tmp/lpi-nonnp.py; chmod 0755 /tmp/lpi-nonnp.py

echo "nobody ставит seccomp-фильтр БЕЗ PR_SET_NO_NEW_PRIVS:"
su -s /bin/sh nobody -c "python3 /tmp/lpi-nonnp.py 63 uname -a" 2>&1 | head -2
echo "(errno 13 = Permission denied: не-root обязан выставить no_new_privs до фильтра)"

rm -f /tmp/lpi-nonnp.py
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-no-new-privs/fix.sh"
