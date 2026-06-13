#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: у дочерней cgroup нет cpu.max, потому что
# контроллер cpu не делегирован через cgroup.subtree_control родителя. Разбор и
# фикс — в README.md рядом.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
CG=/sys/fs/cgroup

rmdir "$CG/lpi-parent/child" 2>/dev/null || true
rmdir "$CG/lpi-parent" 2>/dev/null || true
mkdir -p "$CG/lpi-parent/child"

echo "subtree_control родителя (пусто по умолчанию): '$(cat "$CG/lpi-parent/cgroup.subtree_control")'"
echo "файлы 'cpu*' в дочерней (НЕТ cpu.max):"
( shopt -s nullglob; for f in "$CG/lpi-parent/child"/cpu*; do echo "  ${f##*/}"; done )
echo "пытаемся задать лимит в дочерней:"
sh -c "echo '50000 100000' > $CG/lpi-parent/child/cpu.max" 2>&1; echo "  exit=$?"

rmdir "$CG/lpi-parent/child" 2>/dev/null || true
rmdir "$CG/lpi-parent" 2>/dev/null || true
echo
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-enable-subtree-control/fix.sh"
