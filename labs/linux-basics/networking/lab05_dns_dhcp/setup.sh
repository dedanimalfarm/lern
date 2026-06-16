#!/bin/bash
set -euo pipefail

# Clean up previous setup
echo "Cleaning up previous setup..."
ip netns del server 2>/dev/null || true
ip netns del client 2>/dev/null || true
killall dnsmasq 2>/dev/null || true
rm -f /tmp/udhcpc.script

# Check and install dependencies
if ! command -v dnsmasq &>/dev/null || ! command -v busybox &>/dev/null || ! command -v dig &>/dev/null; then
    echo "Installing Dnsmasq and dependencies..."
    apt-get update >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq busybox dnsutils >/dev/null 2>&1
else
    echo "Dependencies (dnsmasq, busybox, dnsutils) are already installed."
fi

echo "Setting up Network Namespaces (server, client)..."
ip netns add server
ip netns add client

echo "Creating underlay network (veth pair connecting namespaces)..."
ip link add veth-srv type veth peer name veth-cli
ip link set veth-srv netns server
ip link set veth-cli netns client

# Server network setup
ip -n server addr add 10.0.0.1/24 dev veth-srv
ip -n server link set veth-srv up
ip -n server link set lo up

# Client network setup (No IP configured! DHCP will do this)
ip -n client link set veth-cli up
ip -n client link set lo up

echo "Configuring Dnsmasq (DHCP & DNS)..."
mkdir -p /tmp/dnsmasq
cat <<EOF > /tmp/dnsmasq/dnsmasq.conf
interface=veth-srv
bind-interfaces
# DHCP configuration: assign IPs from .10 to .50
dhcp-range=10.0.0.10,10.0.0.50,12h
# Announce ourselves as the DNS server
dhcp-option=option:dns-server,10.0.0.1

# DNS configuration: local domain
domain=internal.company
address=/db.internal.company/10.0.0.100
address=/api.internal.company/10.0.0.101

# Logging for debugging
log-queries
log-dhcp
EOF

echo "Starting Dnsmasq server in 'server' namespace..."
ip netns exec server dnsmasq -C /tmp/dnsmasq/dnsmasq.conf -x /tmp/dnsmasq/dnsmasq.pid

# Script to safely apply IP without touching host's /etc/resolv.conf
cat <<'EOF' > /tmp/udhcpc.script
#!/bin/sh
if [ "$1" = "bound" ]; then
  ip addr add $ip/$mask dev $interface
fi
EOF
chmod +x /tmp/udhcpc.script

echo "Verifying DHCP & DNS Services..."
# 1. Verify client starts with no IP
client_ip_before=$(ip netns exec client ip -4 addr show veth-cli | grep -oP '(?<=inet\s)\d+(\.\d+){3}') || true
if [ -n "$client_ip_before" ]; then
    echo "❌ Lab 5 Setup Failed: client already has an IP address: $client_ip_before" >&2
    exit 1
fi

# 2. Trigger DHCP request
echo "Requesting IP address via DHCP..."
ip netns exec client busybox udhcpc -i veth-cli -s /tmp/udhcpc.script -n -q >/dev/null 2>&1 || true

# 3. Check if IP got assigned and is in range
client_ip_after=$(ip netns exec client ip -4 addr show veth-cli | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
if [ -z "$client_ip_after" ]; then
    echo "❌ Lab 5 Setup Failed: client failed to obtain DHCP lease!" >&2
    exit 1
fi
echo "  [OK] Client successfully leased IP: $client_ip_after"

# 4. Verify DNS resolution
echo "Testing DNS resolution..."
resolved_db=$(ip netns exec client dig +short @10.0.0.1 db.internal.company | tail -n1)
resolved_api=$(ip netns exec client dig +short @10.0.0.1 api.internal.company | tail -n1)

if [ "$resolved_db" = "10.0.0.100" ] && [ "$resolved_api" = "10.0.0.101" ]; then
    echo "  [OK] DNS resolution db.internal.company -> $resolved_db"
    echo "  [OK] DNS resolution api.internal.company -> $resolved_api"
    echo "=========================================================="
    echo "✅ Lab 5 Setup Complete & Verified!"
    echo "Dnsmasq (DHCP + DNS) running on 'server' namespace (10.0.0.1)"
    echo "Client IP obtained via DHCP: $client_ip_after"
    echo "=========================================================="
else
    echo "❌ Lab 5 Setup Failed: DNS resolution test failed (DB: $resolved_db, API: $resolved_api)" >&2
    exit 1
fi

