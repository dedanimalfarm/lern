#!/usr/bin/env bash
# cleanup: сносим скачанные rootfs (+ остатки broken/fix). Контейнеры nspawn
# эфемерны (--pipe, без --boot) — машин в machined не остаётся.
set -uo pipefail
rm -rf /lab/10-nspawn /lab/10-broken /lab/10-fix 2>/dev/null || true
echo "[OK] cleanup 10-rootfs-and-nspawn"
