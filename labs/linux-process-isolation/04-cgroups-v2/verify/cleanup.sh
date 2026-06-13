#!/usr/bin/env bash
# cleanup: выгоняем процессы из листовых cgroup в корень и сносим всё дерево
# lpi-verify. Идемпотентно (зовётся trap'ом run-module.sh и из prepare.sh).
set -uo pipefail
CG=/sys/fs/cgroup
V="$CG/lpi-verify"
[[ -d "$V" ]] || { echo "[OK] cleanup 04-cgroups-v2"; exit 0; }

for leaf in "$V"/*/; do
  [[ -d "$leaf" ]] || continue
  if [[ -f "$leaf/cgroup.procs" ]]; then
    while read -r p; do
      [[ -n "$p" ]] || continue
      kill -9 "$p" 2>/dev/null || true
      echo "$p" > "$CG/cgroup.procs" 2>/dev/null || true
    done < "$leaf/cgroup.procs"
  fi
  rmdir "$leaf" 2>/dev/null || true
done
rmdir "$V" 2>/dev/null || true
echo "[OK] cleanup 04-cgroups-v2"
