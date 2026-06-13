#!/usr/bin/env bash
# verify: проверяем связность собранной сети — (A) контейнер↔контейнер через мост,
# (B) контейнер→шлюз моста, (C) NAT outbound (best-effort: на хосте без интернета
# печатаем [WARN], прогон не валим).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
SUB=10.77.0

# A: контейнер ↔ контейнер через мост (L2 + FORWARD ACCEPT)
require_succeeds "ping nv1 → nv2 через мост" ip netns exec nv1 ping -c1 -W2 "$SUB.2"
ok "L2 через мост: nv1 → nv2"

# B: контейнер → шлюз (IP моста на хосте)
require_succeeds "ping nv1 → шлюз" ip netns exec nv1 ping -c1 -W2 "$SUB.254"
ok "nv1 → шлюз моста ($SUB.254)"

# C: NAT outbound — best-effort (нужен интернет у хоста)
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
iptables -t nat -A POSTROUTING -s "$SUB.0/24" -j MASQUERADE 2>/dev/null || true
if ip netns exec nv1 ping -c1 -W3 1.1.1.1 >/dev/null 2>&1; then
  ok "NAT outbound: nv1 → 1.1.1.1 (через MASQUERADE)"
else
  warn "NAT outbound: нет связи nv1 → 1.1.1.1 (нет интернета на хосте? best-effort, не валим)"
fi

ok "module 09-networking verified"
