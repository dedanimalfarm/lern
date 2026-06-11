#!/bin/bash

# Clean up previous setup
ip netns del server 2>/dev/null
ip netns del client 2>/dev/null
killall dnsmasq 2>/dev/null

echo "Installing Dnsmasq and dependencies..."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq busybox dnsutils >/dev/null 2>&1

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

echo "=========================================================="
echo "✅ Lab 5 Setup Complete!"
echo "Dnsmasq (DHCP + DNS) running on 'server' namespace (10.0.0.1)"
echo ""
echo "Test DHCP:"
echo "  ip netns exec client busybox udhcpc -i veth-cli -s /tmp/udhcpc.script -n -q"
echo "  ip netns exec client ip addr show veth-cli"
echo ""
echo "Test DNS:"
echo "  ip netns exec client dig +short @10.0.0.1 db.internal.company"
echo "=========================================================="
