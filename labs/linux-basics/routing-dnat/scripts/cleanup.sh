#!/bin/bash

echo "Cleaning up Network Namespaces..."

ip netns delete client_ns 2>/dev/null || true
ip netns delete router_ns 2>/dev/null || true
ip netns delete server_ns 2>/dev/null || true

rm -f /tmp/index.html

echo "Cleanup complete!"
