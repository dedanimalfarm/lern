#!/usr/bin/env bash
# Чинит инцидент scenario-01: workdir на той же ФС, что upperdir → mount overlay OK.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }

B=/lab/08-fix
umount "$B/merged" 2>/dev/null || true
rm -rf "$B"
mkdir -p "$B"/{lower,upper,work,merged}
echo base > "$B/lower/f.txt"

echo "mount overlay с workdir на той же ФС, что upper:"
if mount -t overlay overlay -o "lowerdir=$B/lower,upperdir=$B/upper,workdir=$B/work" "$B/merged"; then
  echo "  OK, merged: $(ls "$B/merged")"
  umount "$B/merged" 2>/dev/null || true
fi
rm -rf "$B"
