#!/usr/bin/env bash
# cleanup: сносим netns, мост и добавленные iptables-правила (FORWARD + nat).
set -uo pipefail
BR=lab-br-v
SUB=10.77.0
ip netns del nv1 2>/dev/null || true
ip netns del nv2 2>/dev/null || true
ip link del "$BR" 2>/dev/null || true
iptables -t nat -D POSTROUTING -s "$SUB.0/24" -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -i "$BR" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -o "$BR" -j ACCEPT 2>/dev/null || true
echo "[OK] cleanup 09-networking"
