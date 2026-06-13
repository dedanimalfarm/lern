#!/usr/bin/env bash
# verify: программная проверка целей модуля 01. Печатает [OK]/[FAIL], валится
# на первой непройденной проверке (set -e + `|| fail`). Контракт идентичен
# verify.sh в k8s-лабах.
#
# Доказываем ОБА факта про chroot:
#   - что он изолирует (видимый корень / файловая система);
#   - что он НЕ изолирует (UTS, mount-namespace) и НЕ держит периметр (побег).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin busybox
ROOT=/lab/01-chroot/rootfs
require_file "$ROOT/bin/busybox" "busybox в rootfs (запусти сначала verify/prepare.sh)"

# 1. ФС изолирована: внутри chroot виден НАШ /etc/hostname из rootfs.
INSIDE_HN_FILE=$(chroot "$ROOT" /bin/cat /etc/hostname 2>/dev/null || true)
assert_eq "chroot-jail" "$INSIDE_HN_FILE" "ФС изолирована (/etc/hostname из rootfs)"
ok "ФС изолирована: /etc/hostname внутри = '$INSIDE_HN_FILE'"

# 2. UTS НЕ изолирован: hostname внутри совпадает с хостовым.
HOST_HN=$(hostname)
INSIDE_HN=$(chroot "$ROOT" /bin/hostname 2>/dev/null || true)
assert_eq "$HOST_HN" "$INSIDE_HN" "UTS общий (hostname внутри == host)"
ok "UTS общий: hostname внутри = host = '$HOST_HN'"

# 3. mount-namespace НЕ создаётся: inode mnt-ns внутри == хостовому.
#    Ядро гарантирует разные inode у процессов в разных ns — значит chroot
#    оставляет процесс в ТОМ ЖЕ mnt-ns (никакой изоляции маунтов нет).
HOST_MNT=$(ns_inode mnt)
INSIDE_MNT=$(ns_inode mnt "$ROOT")
assert_eq "$HOST_MNT" "$INSIDE_MNT" "mnt-ns общий (chroot не делает новый namespace)"
ok "mnt-ns общий: inode внутри = host = $HOST_MNT"

# 4. Классический побег работает: у chroot НЕТ защиты периметра. /proc/1/root —
#    magic-symlink ядра на корень PID 1 в его mnt-ns; mnt-ns общий ⇒ это корень
#    хоста ⇒ root внутри chroot выходит наружу одним chroot(2).
require_succeeds "побег chroot через /proc/1/root" \
  chroot "$ROOT" /bin/sh -c 'chroot /proc/1/root /bin/true'
ok "побег /proc/1/root работает — chroot это НЕ песочница (защита — этап 03)"

ok "module 01-chroot verified"
