#!/usr/bin/env bash
# verify: ПЕРЕНОСИМЫЕ проверки capabilities (зелёные и на WSL2, и на реальном хосте):
#   A. capsh --drop убирает привилегию из bounding set;
#   B. setcap/getcap roundtrip — хранение file-capability в xattr;
#   C. ambient enforcement — nobody ровно с cap_chown: CapEff=...0001 и chown работает.
# Headline-enforcement (bind :80 через file-cap) на WSL2 не действует, поэтому в
# verify не входит — он в README/run.sh и проверяется на реальном хосте.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin capsh
need_bin setcap
need_bin getcap

# A: drop одной привилегии из bounding set
BND=$(capsh --drop=cap_net_bind_service --print 2>/dev/null | sed -n 's/^Bounding set =//p' || true)
if printf '%s' "$BND" | grep -q 'cap_net_bind_service'; then
  fail "capsh --drop не убрал cap_net_bind_service из bounding set"
fi
ok "drop: cap_net_bind_service убран из bounding set через capsh --drop"

# B: setcap/getcap roundtrip (хранение file-capability)
BIN=/tmp/lpi-capx
cp /bin/true "$BIN"
setcap cap_net_bind_service+ep "$BIN" 2>/dev/null \
  || fail "setcap не сработал (ФС без xattr security.capability?)"
GC=$(getcap "$BIN" 2>/dev/null || true)
printf '%s' "$GC" | grep -q 'cap_net_bind_service=ep' \
  || fail "getcap не показал '=ep' (получено: '$GC')"
setcap -r "$BIN" 2>/dev/null || true
GC2=$(getcap "$BIN" 2>/dev/null || true)
[[ -z "$GC2" ]] || fail "setcap -r не очистил file-caps (осталось: '$GC2')"
rm -f "$BIN"
ok "file-cap storage: setcap +ep → getcap '...=ep' → setcap -r → пусто"

# C: ambient enforcement — nobody ровно с cap_chown
OUT=$(capsh --keep=1 --user=nobody --inh=cap_chown --addamb=cap_chown -- \
  -c 'grep CapEff /proc/self/status; touch /tmp/lpi-capdemo 2>/dev/null && chown root /tmp/lpi-capdemo 2>/dev/null && echo CHOWN_OK || echo CHOWN_FAIL' 2>&1 || true)
rm -f /tmp/lpi-capdemo
printf '%s\n' "$OUT" | grep -q '0000000000000001' || fail "CapEff != ...0001 (вывод: $OUT)"
printf '%s\n' "$OUT" | grep -q 'CHOWN_OK'          || fail "chown с CAP_CHOWN не сработал (вывод: $OUT)"
ok "enforcement: nobody с одной cap (cap_chown) → CapEff=...0001, chown работает"

ok "module 05-capabilities verified"
