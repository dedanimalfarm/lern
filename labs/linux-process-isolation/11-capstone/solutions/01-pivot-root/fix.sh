#!/usr/bin/env bash
# Контраст к scenario-01: mycontainer использует unshare --mount + pivot_root +
# umount old_root → побег /proc/1/root остаётся ВНУТРИ контейнера (корень alpine).
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }

MYC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/mycontainer.sh"
[[ -x "$MYC" ]] || { echo "не найден mycontainer.sh"; exit 1; }

echo "mycontainer (pivot_root): побег /proc/1/root →"
# shellcheck disable=SC2016  # $(...) раскрывается во ВНУТРЕННЕМ sh контейнера
"$MYC" run alpine -- sh -c 'echo "  hostname: $(hostname)"; echo "  /proc/1/root ls /: $(chroot /proc/1/root /bin/sh -c "ls /" | tr "\n" " ")"' 2>&1 | grep -E 'hostname:|root ls' | head -2
echo "(корень alpine КОНТЕЙНЕРА, а не хоста — pivot_root закрыл побег)"
