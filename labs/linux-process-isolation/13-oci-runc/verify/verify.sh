#!/usr/bin/env bash
# verify: запускаем bundle через runc run и проверяем изоляцию (PID 1=sh,
# hostname=runc, uid=0) и что config.json описывает namespaces. Переносимо
# (runc есть и на WSL2, и на хосте).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin runc
need_bin python3
B=/lab/13-runc/bundle
require_file "$B/config.json" "config.json (запусти verify/prepare.sh)"

runc delete --force lpi-runc-ctr 2>/dev/null || true
OUT=$( cd "$B" || exit 1; runc run lpi-runc-ctr 2>&1 || true )
runc delete --force lpi-runc-ctr 2>/dev/null || true

printf '%s\n' "$OUT" | grep -q '^PID1=sh' || fail "контейнер не отработал через runc. Вывод: $OUT"
ok "runc run: контейнер отработал из OCI-bundle"

printf '%s\n' "$OUT" | grep -q '^HOST=runc' || fail "UTS не изолирован (HOST != runc). Вывод: $OUT"
ok "изоляция: PID 1=sh, hostname=runc (namespaces из config.json)"

printf '%s\n' "$OUT" | grep -q '^UID=0' || fail "uid != 0 внутри. Вывод: $OUT"
ok "внутри uid=0 (root в контейнере)"

NS=$(python3 -c "import json;print(' '.join(n['type'] for n in json.load(open('$B/config.json'))['linux']['namespaces']))" 2>/dev/null || true)
[[ "$NS" == *pid* && "$NS" == *mount* ]] || fail "config.json без namespaces (получено '$NS')"
ok "config.json описывает namespaces: $NS"

ok "module 13-oci-runc verified"
