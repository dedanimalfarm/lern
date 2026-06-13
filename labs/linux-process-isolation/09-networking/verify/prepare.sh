#!/usr/bin/env bash
# prepare: собираем сеть «контейнеров» — мост lab-br-v + два netns (nv1/nv2) на
# veth-парах. Добавляем FORWARD ACCEPT (нужно на br_netfilter-хостах: Docker/WSL2),
# иначе bridged-трафик дропается policy FORWARD=DROP.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin ip
need_bin iptables

# снести residue прошлого прогона
bash "$(dirname "${BASH_SOURCE[0]}")/cleanup.sh" >/dev/null 2>&1 || true

BR=lab-br-v
SUB=10.77.0
ip link add "$BR" type bridge
ip link set "$BR" up
ip addr add "$SUB.254/24" dev "$BR"
iptables -A FORWARD -i "$BR" -j ACCEPT
iptables -A FORWARD -o "$BR" -j ACCEPT

i=1
for ns in nv1 nv2; do
  ip netns add "$ns"
  ip link add "v-$ns" type veth peer name "b-$ns"
  ip link set "b-$ns" master "$BR"
  ip link set "b-$ns" up
  ip link set "v-$ns" netns "$ns"
  ip netns exec "$ns" sh -c "ip addr add $SUB.$i/24 dev v-$ns; ip link set v-$ns up; ip link set lo up; ip route add default via $SUB.254"
  i=$((i + 1))
done

ok "сеть собрана: мост $BR + nv1($SUB.1)/nv2($SUB.2), FORWARD ACCEPT"
