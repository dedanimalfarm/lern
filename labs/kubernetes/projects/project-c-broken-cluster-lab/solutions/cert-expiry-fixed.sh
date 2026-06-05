#!/usr/bin/env bash
# РЕШЕНИЕ cert-expiry: перевыпустить сертификат с актуальным сроком и обновить
# Secret. В проде это делает cert-manager автоматически (модуль 22) — здесь руками,
# чтобы увидеть суть: Secret тот же, начинка свежая.
set -euo pipefail
NS="${1:-lab}"
TMP=$(mktemp -d)

# Валидный сертификат на 365 дней вперёд.
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/tls.key" -out "$TMP/tls.crt" \
  -subj "/CN=incident.local" -days 365 >/dev/null 2>&1

kubectl -n "$NS" create secret tls web-tls \
  --cert="$TMP/tls.crt" --key="$TMP/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

rm -rf "$TMP"
echo "Secret web-tls обновлён валидным сертификатом."
kubectl -n "$NS" get secret web-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -enddate
echo "Проверка checkend 0:"
kubectl -n "$NS" get secret web-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -checkend 0 \
  && echo "  cert ВАЛИДЕН ✓"
