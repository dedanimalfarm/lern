#!/usr/bin/env bash
# cleanup: tmpfs нового корня жил внутри (уже завершившегося) mount-ns, на хосте
# его быть не должно — но на всякий случай умонтируем и сносим каталог.
set -uo pipefail
umount -R /lab/03-pivot-root/newroot 2>/dev/null || umount -l /lab/03-pivot-root/newroot 2>/dev/null || true
rm -rf /lab/03-pivot-root 2>/dev/null || true
echo "[OK] cleanup 03-pivot-root"
