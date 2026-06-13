#!/usr/bin/env bash
# Чинит инцидент scenario-01: добавляем --map-root-user (-r) → внутри uid 0, и
# root-операции (mount) работают в своём namespace.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
command -v unshare >/dev/null || { echo "нет unshare"; exit 1; }

echo "uid внутри (с -r): $(su -s /bin/sh nobody -c 'unshare --user --map-root-user id -u' 2>/dev/null)"
echo "mount с правами root в ns:"
su -s /bin/sh nobody -c 'unshare --user --map-root-user --mount sh -c "mount -t tmpfs none /mnt && echo MOUNT_OK"'
