#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: pivot_root на ОБЫЧНОМ каталоге (не отдельной
# точке монтирования) → EBUSY «Device or resource busy». Разбор и фикс — в README.md.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }

# shellcheck disable=SC2016  # $? раскрывается во ВНУТРЕННЕМ bash (намеренно)
unshare --mount /bin/bash -c '
  mount --make-rprivate / 2>/dev/null || true
  rm -rf /lab/03-broken; install -d /lab/03-broken/newroot/old_root
  cd /lab/03-broken/newroot
  echo "newroot — обычный каталог на той же ФС, что и / :"
  pivot_root . old_root; echo "  exit=$?"
' || true

rm -rf /lab/03-broken 2>/dev/null || true
echo
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-make-mountpoint/fix.sh"
