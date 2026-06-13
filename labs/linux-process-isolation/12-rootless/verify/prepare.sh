#!/usr/bin/env bash
# prepare: модулю 12 не нужны артефакты — только возможность создать
# непривилегированный user-ns. На захардненных хостах (unprivileged_userns_clone=0)
# мягко пропускаем (verify тоже).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin unshare
if ! su -s /bin/sh nobody -c 'unshare --user --map-root-user true' 2>/dev/null; then
  warn "непривилегированные user-namespaces недоступны в ядре (sysctl?) — модуль пропущен"
  exit 0
fi
ok "непривилегированные user-ns доступны (nobody может создать user-ns)"
