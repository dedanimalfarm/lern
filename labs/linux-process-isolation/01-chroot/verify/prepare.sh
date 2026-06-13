#!/usr/bin/env bash
# prepare: детерминированно собираем busybox-rootfs для verify.sh.
# Аналог `kubectl apply manifests/` в k8s-лабах — только «ресурс» здесь это
# каталог-rootfs с примонтированными псевдо-ФС, а не объект в кластере.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin busybox
need_bin chroot

ROOT=/lab/01-chroot/rootfs

# Сносим прошлую сборку (умонтируем псевдо-ФС, чтобы rm не зацепил хостовые).
for m in proc sys dev; do umount -R "$ROOT/$m" 2>/dev/null || umount -l "$ROOT/$m" 2>/dev/null || true; done
rm -rf /lab/01-chroot

install -d -m0755 "$ROOT"/{bin,etc,proc,sys,dev,root,tmp}
chmod 1777 "$ROOT/tmp"

# Статический busybox: один бинарь + симлинки-апплеты, никаких внешних .so —
# поэтому внутри chroot он работает без копирования библиотек (ср. scenario-01).
cp "$(command -v busybox)" "$ROOT/bin/"
for app in sh ls cat echo stat id hostname ps mount uname grep; do
  ln -sf busybox "$ROOT/bin/$app"
done
printf 'chroot-jail\n' > "$ROOT/etc/hostname"

# /proc нужен для чтения /proc/self/ns/* и для побега через /proc/1/root;
# /dev — чтобы шелл не падал на отсутствии /dev/null; /sys — для полноты.
mount --rbind /dev "$ROOT/dev"
mount --make-rslave "$ROOT/dev"
mount -t proc proc "$ROOT/proc"
mount -t sysfs sys "$ROOT/sys"

ok "rootfs готов: $ROOT (busybox + /proc,/sys,/dev)"
