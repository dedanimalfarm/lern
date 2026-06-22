#!/usr/bin/env bash
set -euo pipefail

echo "Verifying module 18..."

# 1. Check loki is ready
kubectl -n lab rollout status deploy/loki --timeout=30s >/dev/null 2>&1 || {
  echo "[FAIL] loki is not ready"
  exit 1
}
echo "[OK] loki is ready"

# Wait a bit for logs to be shipped and processed
sleep 5

# Helper function to query loki
query_loki() {
  local query="$1"
  local enc
  enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$query")
  kubectl -n lab exec deploy/loki -- wget -qO- "http://localhost:3100/loki/api/v1/query?query=${enc}" 2>/dev/null
}

# 2. Check logs are delivered
RES=$(query_loki '{app="payment-api"}')
if echo "$RES" | grep -q '"status":"success"'; then
  if echo "$RES" | grep -q '"result":\s*\['; then
    # Ensure result array is not empty (it has something after bracket)
    if echo "$RES" | grep -q '"result":\s*\[\s*{'; then
      echo "[OK] логи доставляются: payment-api виден в Loki"
    else
      echo "[FAIL] payment-api logs not found in Loki (result empty)"
      exit 1
    fi
  else
    echo "[FAIL] payment-api logs not found in Loki"
    exit 1
  fi
else
  echo "[FAIL] failed to query Loki for payment-api logs"
  exit 1
fi

# 3. Check json parser works
RES_JSON=$(query_loki '{app="payment-api"} | json | status>=500')
if echo "$RES_JSON" | grep -q '"result":\s*\[\s*{'; then
  echo "[OK] json-парсер работает: status>=500 находятся"
else
  echo "[FAIL] json parser or status>=500 query failed"
  exit 1
fi

# 4. Check metrics from logs
RES_METRICS=$(query_loki 'rate({app="payment-api"} | json | __error__="" [5m])')
if echo "$RES_METRICS" | grep -q '"result":\s*\[\s*{'; then
  echo "[OK] метрики из логов: rate() > 0"
else
  echo "[FAIL] metrics query failed"
  exit 1
fi

echo "[OK] module 18 verified"
