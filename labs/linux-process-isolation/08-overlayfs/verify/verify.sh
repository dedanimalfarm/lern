#!/usr/bin/env bash
# verify: проверяем три факта overlay — (1) merged = union (виден lower);
# (2) CoW (запись копирует в upper, lower цел); (3) whiteout (удаление → char
# device 0,0 в upper, файл скрыт в merged, но жив в lower).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
B=/lab/08-overlayfs
require_file "$B/merged/file.txt" "merged/file.txt (запусти verify/prepare.sh)"

# 1) merged видит файл из lower
assert_eq "original content" "$(cat "$B/merged/file.txt" 2>/dev/null || true)" "merged видит файл из lower"
ok "merged = union: виден файл из lower"

# 2) CoW: запись в merged не трогает lower, уходит в upper
echo "modified" > "$B/merged/file.txt"
assert_eq "original content" "$(cat "$B/lower/file.txt" 2>/dev/null || true)" "CoW: lower не изменён"
assert_eq "modified"        "$(cat "$B/upper/file.txt" 2>/dev/null || true)" "CoW: upper получил copy-up"
ok "CoW: правка в merged ушла в upper, lower защищён"

# 3) whiteout при удалении файла из lower
rm "$B/merged/to-delete.txt"
FT=$(stat -c '%F' "$B/upper/to-delete.txt" 2>/dev/null || true)
[[ "$FT" == "character special file" ]] || fail "whiteout не char device (тип: '$FT')"
MAJ=$(stat -c '%t' "$B/upper/to-delete.txt" 2>/dev/null || true)
MIN=$(stat -c '%T' "$B/upper/to-delete.txt" 2>/dev/null || true)
[[ "$MAJ" == "0" && "$MIN" == "0" ]] || fail "whiteout device != 0,0 (получено $MAJ,$MIN)"
[[ ! -e "$B/merged/to-delete.txt" ]] || fail "merged всё ещё показывает удалённый файл"
[[ -f "$B/lower/to-delete.txt" ]]    || fail "lower потерял файл (должен оставаться жив)"
ok "whiteout: char device 0,0 в upper, файл скрыт в merged, жив в lower"

ok "module 08-overlayfs verified"
