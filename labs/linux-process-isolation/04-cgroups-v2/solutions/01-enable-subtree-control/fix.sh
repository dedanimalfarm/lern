#!/usr/bin/env bash
# Чинит инцидент scenario-01: включаем контроллер cpu в cgroup.subtree_control
# РОДИТЕЛЯ — после этого в дочерней cgroup появляется cpu.max и лимит можно задать.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
CG=/sys/fs/cgroup

rmdir "$CG/lpi-parent/child" 2>/dev/null || true
rmdir "$CG/lpi-parent" 2>/dev/null || true
mkdir -p "$CG/lpi-parent/child"

echo "включаем +cpu в subtree_control РОДИТЕЛЯ:"
echo +cpu > "$CG/lpi-parent/cgroup.subtree_control" \
  && echo "  subtree_control = '$(cat "$CG/lpi-parent/cgroup.subtree_control")'"
if [[ -e "$CG/lpi-parent/child/cpu.max" ]]; then echo "теперь в дочерней есть cpu.max"; else echo "cpu.max всё ещё нет"; fi
echo "50000 100000" > "$CG/lpi-parent/child/cpu.max" \
  && echo "  лимит задан: cpu.max = $(cat "$CG/lpi-parent/child/cpu.max")"

# уборка
rmdir "$CG/lpi-parent/child" 2>/dev/null || true
echo -cpu > "$CG/lpi-parent/cgroup.subtree_control" 2>/dev/null || true
rmdir "$CG/lpi-parent" 2>/dev/null || true
