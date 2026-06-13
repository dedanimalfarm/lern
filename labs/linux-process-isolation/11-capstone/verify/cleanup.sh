#!/usr/bin/env bash
# cleanup: размонтируем возможные overlay контейнеров, сносим состояние и cgroup,
# убираем наивный rootfs из scenario-01. На случай, если контейнер упал до уборки.
set -uo pipefail
mount 2>/dev/null | grep -o '/var/lib/mycontainer/[^ ]*/merged' | sort -u | while read -r m; do
  umount -l "$m" 2>/dev/null || true
done
rm -rf /var/lib/mycontainer/* 2>/dev/null || true
for c in /sys/fs/cgroup/mycontainer-* /sys/fs/cgroup/mycontainer/myc-*; do
  [[ -d "$c" ]] || continue
  rmdir "$c" 2>/dev/null || true
done
rm -rf /lab/11-naive 2>/dev/null || true
echo "[OK] cleanup 11-capstone"
