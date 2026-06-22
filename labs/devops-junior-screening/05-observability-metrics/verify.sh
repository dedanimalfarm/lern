#!/usr/bin/env bash
set -euo pipefail

echo "==> Проверка модуля 05: Observability — метрики"

echo "1) Проверка запущенных контейнеров..."
if ! docker ps | grep -q prometheus; then
  echo "[ERR] Контейнер prometheus не запущен."
  exit 1
fi
if ! docker ps | grep -q node-exporter; then
  echo "[ERR] Контейнер node-exporter не запущен."
  exit 1
fi
if ! docker ps | grep -q grafana; then
  echo "[ERR] Контейнер grafana не запущен."
  exit 1
fi
echo "[OK] Контейнеры запущены."

echo "2) Проверка доступности endpoints..."
if ! curl -sSf http://127.0.0.1:9090/-/healthy >/dev/null; then
  echo "[ERR] Prometheus не отвечает на /-/healthy."
  exit 1
fi
if ! curl -sSf http://127.0.0.1:9100/metrics >/dev/null; then
  echo "[ERR] node-exporter не отдает метрики."
  exit 1
fi
if ! curl -sSf http://127.0.0.1:3000/api/health >/dev/null; then
  echo "[ERR] Grafana API не отвечает."
  exit 1
fi
echo "[OK] Эндпоинты доступны."

echo "3) Проверка targets в Prometheus..."
TARGETS=$(curl -s http://127.0.0.1:9090/api/v1/targets | grep -c '"health":"up"' || true)
if [ "$TARGETS" -lt 2 ]; then
  echo "[WARN] Менее двух targets 'up'. Проверьте настройки в prometheus.yml."
else
  echo "[OK] Найдено как минимум $TARGETS targets 'up'."
fi

echo "==> Все базовые проверки пройдены!"
