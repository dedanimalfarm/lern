#!/usr/bin/env bash
# Чинит инцидент scenario-01: настоящий seccomp_bpf.py ВЫЗЫВАЕТ
# prctl(PR_SET_NO_NEW_PRIVS) перед фильтром → не-root может его поставить
# (uname получает SIGSYS, а не EACCES).
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
command -v python3 >/dev/null || { echo "нет python3"; exit 1; }

HELP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/seccomp_bpf.py"
cp "$HELP" /tmp/lpi-scbpf.py; chmod 0755 /tmp/lpi-scbpf.py

echo "nobody с настоящим seccomp_bpf.py (ставит PR_SET_NO_NEW_PRIVS):"
su -s /bin/sh nobody -c "python3 /tmp/lpi-scbpf.py 63 uname -a" 2>&1 | head -2
echo "(uname убит SIGSYS — фильтр применился у не-root, без errno 13)"

rm -f /tmp/lpi-scbpf.py
