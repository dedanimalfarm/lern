#!/usr/bin/env bash
# ИНЦИДЕНТ CERT-EXPIRY: создаёт TLS-Secret с УЖЕ ПРОСРОЧЕННЫМ самоподписанным
# сертификатом (notAfter в прошлом). Симптом в проде: TLS-хендшейк падает «тихо»
# (браузер/клиент ругается на cert), приложение вроде живо — это самый коварный
# класс инцидентов, т.к. не виден в статусе пода. Диагностика — проверять срок.
set -euo pipefail
NS="${1:-lab}"
TMP=$(mktemp -d)

# Сертификат, истёкший ещё в 2024 (openssl 3.x: -not_before/-not_after).
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/tls.key" -out "$TMP/tls.crt" \
  -subj "/CN=incident.local" \
  -not_before 20240101000000Z -not_after 20240102000000Z >/dev/null 2>&1

kubectl -n "$NS" create secret tls web-tls \
  --cert="$TMP/tls.crt" --key="$TMP/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

rm -rf "$TMP"
echo "Secret web-tls создан в ns/$NS с ПРОСРОЧЕННЫМ сертификатом (notAfter в 2024)."
echo "Диагностика:"
echo "  kubectl -n $NS get secret web-tls -o jsonpath='{.data.tls\\.crt}' | base64 -d | openssl x509 -noout -enddate -checkend 0"
