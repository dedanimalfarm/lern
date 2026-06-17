#!/usr/bin/env bash
# run-all-networking.sh: Run setup -> verify -> cleanup for all networking labs.
set -uo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "запусти как root: sudo ./run-all-networking.sh" >&2
  exit 1
fi

NET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$NET_DIR" || exit 1

C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'

LABS=(
  "lab01-routing-dnat"
  "lab02-loadbalancer"
  "lab03-wireguard"
  "lab04-vlan"
  "lab05-dns-dhcp"
  "lab06-linux-bridge"
  "lab07-ip-nftables"
  "lab09-traffic-control"
  "lab10-bgp"
  "lab11-mini-docker"
  "lab12-cni-intro"
)

OK=()
FAIL=()

for lab in "${LABS[@]}"; do
  echo "############################################################"
  echo "##  LAB: $lab"
  echo "############################################################"
  
  # Ensure we clean up any previous failures first
  if [[ "$lab" == "lab01-routing-dnat" ]]; then
    (cd "$lab/scripts" && chmod +x *.sh && ./cleanup.sh >/dev/null 2>&1 || true)
  elif [[ -f "$lab/cleanup.sh" ]]; then
    (cd "$lab" && chmod +x *.sh && ./cleanup.sh >/dev/null 2>&1 || true)
  fi

  # Run Setup
  STATUS=0
  if [[ "$lab" == "lab01-routing-dnat" ]]; then
    echo "Running setup..."
    (cd "$lab/scripts" && ./setup.sh) || STATUS=1
    sleep 2
    if [[ $STATUS -eq 0 ]]; then
      echo "Applying routing/DNAT solution..."
      ip netns exec client_ns ip route add default via 10.0.1.1 || STATUS=1
      ip netns exec server_ns ip route add default via 10.0.2.1 || STATUS=1
      ip netns exec router_ns sysctl -w net.ipv4.ip_forward=1 >/dev/null || STATUS=1
      ip netns exec router_ns iptables -t nat -A PREROUTING -d 10.0.1.1 -p tcp --dport 80 -j DNAT --to-destination 10.0.2.2:8080 || STATUS=1
    fi
  elif [[ "$lab" == "lab11-mini-docker" ]]; then
    echo "Running setup (mini-docker run)..."
    (cd "$lab" && chmod +x *.sh && bash mini-docker.sh run myweb 8080:80) || STATUS=1
    sleep 2
  else
    echo "Running setup..."
    (cd "$lab" && chmod +x *.sh && ./setup.sh) || STATUS=1
    if [[ "$lab" == "lab10-bgp" ]]; then
      sleep 8
    else
      sleep 2
    fi
  fi

  # Run Verify
  if [[ $STATUS -eq 0 ]]; then
    echo "Running verification..."
    if [[ "$lab" == "lab01-routing-dnat" ]]; then
      (cd "$lab/scripts" && ./verify.sh) || STATUS=1
    else
      (cd "$lab" && ./verify.sh) || STATUS=1
    fi
  else
    echo "Setup failed! Skipping verification."
  fi

  # Run Cleanup
  echo "Running cleanup..."
  if [[ "$lab" == "lab01-routing-dnat" ]]; then
    (cd "$lab/scripts" && ./cleanup.sh) || true
  elif [[ -f "$lab/cleanup.sh" ]]; then
    (cd "$lab" && ./cleanup.sh) || true
  fi

  if [[ $STATUS -eq 0 ]]; then
    echo "Result: PASS"
    OK+=("$lab")
  else
    echo "Result: FAIL"
    FAIL+=("$lab")
  fi
  echo ""
done

echo "============================================================"
echo "NETWORKING LABS SUMMARY:"
echo "============================================================"
for l in "${OK[@]}";   do printf "  %s✓ PASS%s   %s\n" "$C_GREEN" "$C_RESET" "$l"; done
for l in "${FAIL[@]}"; do printf "  %s✗ FAIL%s   %s\n" "$C_RED"   "$C_RESET" "$l"; done

echo
echo "PASS: ${#OK[@]}  FAIL: ${#FAIL[@]}"
[[ ${#FAIL[@]} -eq 0 ]]
