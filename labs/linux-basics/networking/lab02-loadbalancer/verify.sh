#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Verifying Lab 2 (HAProxy Load Balancer)..."

# 1. Check if HAProxy is running
if ! pgrep haproxy >/dev/null 2>&1; then
    echo "[FAIL] HAProxy is not running!"
    exit 1
fi

# 2. Check if Python web servers are running
web_servers_count=$(pgrep -f "http.server 808" | wc -l)
if [ "$web_servers_count" -lt 3 ]; then
    echo "[FAIL] Not all Python backend servers are running (found $web_servers_count/3)."
    exit 1
fi
echo "  [OK] HAProxy and Python web servers are running."

# 3. Verify load balancing (send requests and collect responses)
responses=$(curl -s --connect-timeout 2 http://localhost:8080 && echo "" && \
             curl -s --connect-timeout 2 http://localhost:8080 && echo "" && \
             curl -s --connect-timeout 2 http://localhost:8080) || true

unique_servers=$(echo "$responses" | grep -o 'Server [123]' | sort -u | wc -l)

if [ "$unique_servers" -ge 2 ]; then
    echo "  [OK] Round-robin load balancing is active. Responses received from multiple backends."
else
    echo "[FAIL] Load balancing verification failed. Response: "
    echo "$responses"
    exit 1
fi

# 4. Verify statistics page is running
if ! curl -fsS --connect-timeout 2 http://localhost:8404/ >/dev/null; then
    echo "[FAIL] HAProxy statistics page on port 8404 is not responding."
    exit 1
fi
echo "  [OK] HAProxy statistics page is accessible on port 8404."

echo "✅ Lab 2 Verification Successful!"
exit 0
