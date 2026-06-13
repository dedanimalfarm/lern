#!/usr/bin/env bash
# verify: от непривилегированного nobody проверяем суть rootless — (1) внутри
# user-ns uid=0, (2) файл, созданный 'root' внутри, на хосте принадлежит nobody,
# (3) single-uid маппинг 0→nobody. Если user-ns в ядре выключены — мягкий пропуск.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin unshare
if ! su -s /bin/sh nobody -c 'unshare --user --map-root-user true' 2>/dev/null; then
  warn "непривилегированные user-namespaces недоступны — модуль пропущен (host gate)"
  exit 0
fi
NB=$(id -u nobody)

# 1. внутри user-ns uid 0
IN=$(su -s /bin/sh nobody -c 'unshare --user --map-root-user id -u' 2>/dev/null || true)
[[ "$IN" == "0" ]] || fail "внутри user-ns uid != 0 (получено '$IN')"
ok "rootless: внутри user-ns uid=0 (root)"

# 2. файл от 'root' внутри на хосте принадлежит nobody
F=/tmp/lpi-rootless-test
rm -f "$F"
su -s /bin/sh nobody -c "unshare --user --map-root-user sh -c 'touch $F'" 2>/dev/null || true
OWN=$(stat -c '%u' "$F" 2>/dev/null || echo none)
rm -f "$F"
[[ "$OWN" == "$NB" ]] || fail "файл от 'root' внутри принадлежит uid=$OWN, ожидался nobody ($NB)"
ok "rootless: файл от 'root' внутри на хосте принадлежит nobody (uid $NB), НЕ root"

# 3. single-uid маппинг 0 -> nobody
MAP=$(su -s /bin/sh nobody -c 'unshare --user --map-root-user cat /proc/self/uid_map' 2>/dev/null | tr -s ' ' || true)
[[ "$MAP" == *"0 $NB 1"* ]] || fail "uid_map не single '0 $NB 1' (получено: '$MAP')"
ok "uid_map: 0→$NB (root внутри = nobody снаружи, single-uid)"

ok "module 12-rootless verified"
