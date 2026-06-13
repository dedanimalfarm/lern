#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: unshare --user БЕЗ --map-root-user → внутри
# ты nobody (65534), не root; root-операции (mount) падают.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
command -v unshare >/dev/null || { echo "нет unshare"; exit 1; }

echo "uid внутри (без -r): $(su -s /bin/sh nobody -c 'unshare --user id -u' 2>/dev/null)"
echo "попытка mount (нужен root в ns):"
su -s /bin/sh nobody -c 'unshare --user --mount sh -c "mount -t tmpfs none /mnt 2>&1 | head -1"'
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-map-root/fix.sh"
