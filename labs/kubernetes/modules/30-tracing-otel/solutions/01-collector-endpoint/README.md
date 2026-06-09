# Решение сценария 01

Ошибка: exporter `otlp/tempo` в ConfigMap `otel-collector-config` указывал на
`tempo.lab.svc.cluster.local:3200` — HTTP **query**-порт Tempo. Спаны по
OTLP/gRPC туда не принимаются, экспорт коллектора бесконечно ретраился.

Правильный endpoint — **`tempo.lab.svc.cluster.local:4317`** (OTLP/gRPC ingest,
объявлен в `distributor.receivers.otlp` конфига Tempo).

```bash
# Эталонный конфиг лежит в manifests/ модуля:
kubectl apply -f ../../manifests/otel-collector.yaml
# Коллектор читает конфиг только на старте:
kubectl -n lab rollout restart deploy/otel-collector
kubectl -n lab rollout status deploy/otel-collector --timeout=120s

# Подтверждение: в логах коллектора пропали rpc error, а в Tempo
# появляются свежие traceID:
kubectl -n lab logs deploy/otel-collector --tail=10
kubectl -n lab exec deploy/frontend -- wget -qO- \
  'http://tempo:3200/api/search?tags=service.name%3Dfrontend&limit=3'
```

Диагностическая цепочка и выводы — в `broken/scenario-01/README.md`.
