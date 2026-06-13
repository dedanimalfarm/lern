#!/usr/bin/env bash
# cleanup: размонтируем overlay и сносим слои (+ возможные остатки broken/fix).
set -uo pipefail
B=/lab/08-overlayfs
umount "$B/merged" 2>/dev/null || umount -l "$B/merged" 2>/dev/null || true
rm -rf "$B" /lab/08-broken /lab/08-fix 2>/dev/null || true
echo "[OK] cleanup 08-overlayfs"
