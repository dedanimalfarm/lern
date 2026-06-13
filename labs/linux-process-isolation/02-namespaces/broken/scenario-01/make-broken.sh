#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: PID-namespace «не как в Docker», потому что
# забыты --fork и/или --mount-proc. Разбор и фикс — в README.md рядом.
# shellcheck disable=SC2016  # $$ и $() намеренно раскрываются во ВНУТРЕННЕМ bash
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }

echo "(A) --pid без --fork → \$\$ НЕ равен 1 (сам unshare остался в старом ns):"
unshare --pid /bin/bash -c 'echo "  PID внутри: $$ (ожидали 1)"' || true

echo
echo "(B) --pid --fork БЕЗ --mount-proc → /proc хостовый, ps ломается:"
unshare --pid --fork /bin/bash -c '
  echo "  \$\$=$$"
  ps -e --no-headers 2>&1 | head -2
  echo "  процессов в ps: $(ps -e --no-headers 2>/dev/null | wc -l)"
' || true

echo
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-pid-fork-mountproc/fix.sh"
