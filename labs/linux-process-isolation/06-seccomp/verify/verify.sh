#!/usr/bin/env bash
# verify: ставим raw seccomp-bpf через seccomp_bpf.py (без systemd, переносимо) и
# доказываем: (A) запрещённый syscall убивает процесс SIGSYS, (B) незатронутая
# команда работает, (C) /proc/self/status показывает Seccomp=2 (MODE_FILTER).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin python3
HELP="$ROOT_DIR/06-seccomp/seccomp_bpf.py"
require_file "$HELP" "seccomp_bpf.py"

# A: uname (syscall 63) под фильтром → процесс убит SIGSYS (rc!=0).
# Захват кода через 'echo $?' внутри сабшелла не даёт job-сообщению «Bad system
# call» (от смерти по сигналу) утечь в вывод verify.
RC=$( ( "$HELP" 63 uname -a >/dev/null 2>&1; echo $? ) 2>/dev/null )
[[ "${RC:-0}" -ne 0 ]] || fail "uname под seccomp-фильтром не упал (rc=$RC) — фильтр не применился"
ok "блокировка uname (syscall 63) → процесс убит SIGSYS (rc=$RC)"

# B: незатронутая команда (date не зовёт uname) работает под тем же фильтром.
"$HELP" 63 date >/dev/null 2>&1 || fail "date под фильтром на uname не отработал (фильтр шире, чем надо)"
ok "незатронутая команда (date) под тем же фильтром работает"

# C: фильтр виден в /proc/self/status как MODE_FILTER.
MODE=$("$HELP" 63 cat /proc/self/status 2>/dev/null | awk '/^Seccomp:/{print $2}' || true)
[[ "$MODE" == "2" ]] || fail "Seccomp mode='$MODE', ожидался 2 (MODE_FILTER)"
ok "после prctl: /proc/self/status Seccomp=2 (MODE_FILTER)"

ok "module 06-seccomp verified"
