#!/usr/bin/env bash
# prepare: создаём хостовый каталог под new_root и проверяем инструменты. Сам
# pivot_root (с tmpfs и rootfs) выполняется внутри unshare в verify.sh — он
# эфемерен (живёт только в mount-ns), поэтому пред-собрать его здесь нельзя.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin unshare
need_bin busybox
install -d /lab/03-pivot-root/newroot
ok "окружение готово: /lab/03-pivot-root (unshare/busybox на месте)"
