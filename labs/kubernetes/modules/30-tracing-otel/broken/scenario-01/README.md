# Сценарий 01: трейсы пропали (экспорт коллектора в никуда)

## Симптом

Приложения работают, ошибок в их логах нет, loadgen гоняет трафик — но в Tempo
**не появляются новые трейсы** (Grafana Explore пуст, `/api/search` возвращает
старые traceID или ничего).

## Воспроизведение

```bash
kubectl apply -f collector-config-broken.yaml
# Коллектор НЕ перечитывает конфиг сам — нужен рестарт (это часть урока):
kubectl -n lab rollout restart deploy/otel-collector
kubectl -n lab rollout status deploy/otel-collector --timeout=120s
```

## Ожидаемая диагностика (путь студента)

1. **Приложение?** Логи frontend/backend чистые, под Ready — значит, SDK спаны
   отправляет (иначе в логах были бы ошибки экспорта от
   `opentelemetry-instrument`).
2. **Коллектор?** `kubectl -n lab logs deploy/otel-collector --tail=30`:
   - `debug` exporter печатает батчи (`TracesExporter ... resource spans: N`) —
     значит, спаны ДО коллектора доходят;
   - рядом — ошибки `otlp/tempo`: `rpc error: ... connection error` /
     `retrying`, имя экспортёра в сообщении.
3. **Вывод:** разрыв на участке коллектор → Tempo. Смотрим endpoint в конфиге:
   `tempo.lab.svc.cluster.local:3200` — это **HTTP query API** Tempo (им
   пользуется Grafana), а **OTLP/gRPC ingest живёт на 4317**.

## Починка

```bash
kubectl apply -f ../../manifests/otel-collector.yaml   # правильный endpoint :4317
kubectl -n lab rollout restart deploy/otel-collector
# Проверка: через ~10с в Tempo снова появляются свежие трейсы
```

Решение целиком: `solutions/01-collector-endpoint/`.

## Мораль

- Путь спана — это **цепочка**: SDK → collector receiver → processor → exporter
  → backend ingest. Ломается всегда какое-то ОДНО звено; диагностика — это
  бинарный поиск по цепочке («до коллектора доходит? после — уходит?»).
- `debug` exporter в пайплайне — дешёвый «щуп» для точки «дошло до коллектора».
- У бэкендов трассировки **разные порты для приёма и для запросов** (Tempo:
  4317/4318 ingest vs 3200 query) — перепутать их при настройке проще простого.
- ConfigMap-изменение «молча» не действует: коллектор читает конфиг при старте,
  не забывайте `rollout restart`.
