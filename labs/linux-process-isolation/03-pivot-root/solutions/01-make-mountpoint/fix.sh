#!/usr/bin/env bash
# Чинит инцидент scenario-01: делаем new_root отдельной точкой монтирования
# (tmpfs) — после этого pivot_root проходит, и старый корень убирается umount'ом.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }

unshare --mount --fork /bin/bash -c '
  mount --make-rprivate / 2>/dev/null || true
  rm -rf /lab/03-fix; install -d /lab/03-fix/newroot
  mount -t tmpfs none /lab/03-fix/newroot          # теперь new_root — отдельный mount point
  install -d /lab/03-fix/newroot/{bin,old_root}
  cp /bin/busybox /lab/03-fix/newroot/bin/
  ln -sf busybox /lab/03-fix/newroot/bin/sh
  cd /lab/03-fix/newroot
  pivot_root . old_root && echo "pivot_root OK (newroot стал /)"
  /bin/busybox umount -l /old_root && echo "old_root отмонтирован — побег закрыт"
' || true

rm -rf /lab/03-fix 2>/dev/null || true
