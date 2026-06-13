#!/usr/bin/env bash
# prepare: убеждаемся, что cgroup v2 примонтирована и нужные контроллеры
# делегированы из корня (top-down), а также сносим возможный остаток прошлого
# прогона. Сами тестовые cgroup создаёт verify.sh.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
[[ -f /sys/fs/cgroup/cgroup.controllers ]] || fail "cgroup v2 не примонтирована (/sys/fs/cgroup)"

# снести residue прошлого прогона
bash "$(dirname "${BASH_SOURCE[0]}")/cleanup.sh" >/dev/null 2>&1 || true

# контроллеры должны быть в subtree_control КОРНЯ, иначе lpi-verify их не включит
for c in cpu memory pids; do
  grep -qw "$c" /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null \
    || echo "+$c" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
done
ok "cgroup v2 на месте, контроллеры делегированы (cpu/memory/pids)"
