#!/usr/bin/env bash
# cleanup: удаляем возможный оставшийся контейнер runc и bundle-каталоги.
set -uo pipefail
runc delete --force lpi-runc-ctr 2>/dev/null || true
rm -rf /lab/13-runc /lab/13-broken /lab/13-fix 2>/dev/null || true
echo "[OK] cleanup 13-oci-runc"
