#!/usr/bin/env bash
# cleanup: умонтируем псевдо-ФС и сносим rootfs. Запускается trap'ом из
# run-module.sh ВСЕГДА (в т.ч. при падении verify), иначе в /lab останутся
# примонтированные /proc,/sys,/dev. Снимаем и поломку из scenario-01.
set -uo pipefail
ROOT=/lab/01-chroot/rootfs
for m in proc sys dev; do
  umount -R "$ROOT/$m" 2>/dev/null || umount -l "$ROOT/$m" 2>/dev/null || true
done
rm -rf /lab/01-chroot /lab/01-chroot-broken 2>/dev/null || true
echo "[OK] cleanup 01-chroot"
