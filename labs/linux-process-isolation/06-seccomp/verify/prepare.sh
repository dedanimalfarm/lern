#!/usr/bin/env bash
# prepare: модулю 06 не нужны персистентные артефакты — нужен только python3 и
# helper seccomp_bpf.py. Фильтры эфемерны (живут в процессе, исчезают с ним).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin python3
HELP="$ROOT_DIR/06-seccomp/seccomp_bpf.py"
require_file "$HELP" "seccomp_bpf.py"
[[ -x "$HELP" ]] || chmod +x "$HELP" 2>/dev/null || true
ok "python3 и seccomp_bpf.py на месте"
