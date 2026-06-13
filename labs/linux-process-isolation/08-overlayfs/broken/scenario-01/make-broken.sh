#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: workdir на tmpfs, upperdir на ext4 (/lab) —
# разные ФС → mount overlay падает (rename между ФС невозможен).
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }

B=/lab/08-broken
umount "$B/merged" 2>/dev/null || true
umount "$B/worktmp" 2>/dev/null || true
rm -rf "$B"
mkdir -p "$B"/{lower,upper,merged,worktmp}
echo base > "$B/lower/f.txt"
mount -t tmpfs none "$B/worktmp"
mkdir -p "$B/worktmp/work"

echo "mount overlay с workdir на tmpfs (upper на ext4 — РАЗНЫЕ ФС):"
mount -t overlay overlay -o "lowerdir=$B/lower,upperdir=$B/upper,workdir=$B/worktmp/work" "$B/merged" 2>&1
echo "  exit=$?"
echo "-- точная причина в dmesg:"
dmesg 2>/dev/null | grep -i overlayfs | tail -1

umount "$B/worktmp" 2>/dev/null || true
rm -rf "$B"
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-same-filesystem/fix.sh"
