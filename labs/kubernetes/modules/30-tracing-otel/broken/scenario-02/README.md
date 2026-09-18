# Сценарий 02: Трейсы frontend пропали, в его логах — ошибки экспорта

## Симптом

В отличие от сценария 01, приложение **жалуется**:

```bash
kubectl -n lab logs deploy/frontend --tail=20 | grep -i -E 'export|otlp|unavailable' | tail -2
# Failed to export span batch code: StatusCode.UNAVAILABLE, reason: ... failed to connect to all addresses
```
Backend продолжает отдавать спаны, frontend — нет; trace обрывается на первом хопе.

## Запуск

```bash
bash broken/scenario-02/setup.sh
sleep 30; kubectl -n lab logs deploy/frontend --tail=20 | grep -i -c 'export'
```

## Задание

1. Сравните переменные `OTEL_EXPORTER_OTLP_*` у frontend и backend.
2. Объясните, почему коллектор «слушает», а gRPC-экспортёр всё равно не может подключиться.
3. Исправьте и убедитесь, что trace снова проходит frontend → backend.

Начните:

```bash
kubectl -n lab set env deploy/frontend --list | grep OTEL
kubectl -n lab get svc otel-collector -o jsonpath='{range .spec.ports[*]}{.name}={.port} {end}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

У коллектора два OTLP-приёмника: gRPC на 4317 и HTTP на 4318. Frontend шлёт gRPC (`OTEL_EXPORTER_OTLP_PROTOCOL=grpc`) на порт 4318 — HTTP-приёмник не понимает gRPC-фреймы.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Endpoint и протокол должны совпадать парой: `grpc` ↔ `:4317`, `http/protobuf` ↔ `:4318/v1/traces`.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- OTLP существует в двух транспортах с разными портами по умолчанию. Экспортёр gRPC на
  HTTP-порту получает не-gRPC ответ и считает адрес недоступным → `StatusCode.UNAVAILABLE`,
  батчи спанов отбрасываются после ретраев.
- Симптом «в логах ошибки экспорта» отличает этот случай от сценария 01 (там конвейер
  тихо терял данные дальше по цепочке).
- Проверка пары endpoint/protocol — первый шаг чек-листа модуля.

</details>

<details>
<summary><strong>Решение</strong></summary>

Вернуть gRPC-порт — `solutions/scenario-02/fix.sh`:

```bash
bash solutions/scenario-02/fix.sh
sleep 30; kubectl -n lab logs deploy/frontend --tail=20 | grep -i -c 'export'      # 0
```

</details>
