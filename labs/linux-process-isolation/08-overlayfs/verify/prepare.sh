#!/usr/bin/env bash
# prepare: собираем слои в /lab/08-overlayfs и монтируем overlay (lower+upper+work
# на одной ФС). Сами CoW/whiteout-операции делает verify.sh.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
grep -qw overlay /proc/filesystems 2>/dev/null || modprobe overlay 2>/dev/null || true
grep -qw overlay /proc/filesystems 2>/dev/null || fail "overlayfs недоступен в ядре"

B=/lab/08-overlayfs
umount "$B/merged" 2>/dev/null || true
rm -rf "$B"
mkdir -p "$B"/{lower,upper,work,merged}
echo "original content" > "$B/lower/file.txt"
echo "delete-me"        > "$B/lower/to-delete.txt"
mount -t overlay overlay -o "lowerdir=$B/lower,upperdir=$B/upper,workdir=$B/work" "$B/merged" \
  || fail "mount overlay не удался (см. dmesg | tail)"
ok "overlay смонтирован: lower+upper+work → merged"
