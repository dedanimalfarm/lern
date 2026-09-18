# 04 — KEDA: масштабирование по событиям и в ноль

## Задача
Увидеть то, чего HPA не умеет: масштабировать Deployment **в ноль** и обратно по внешнему
триггеру. Триггер — `cron` (не нужны очередь и Prometheus): каждую чётную минуту KEDA
поднимает 2 реплики, каждую нечётную — гасит до нуля.

KEDA не входит в аддоны стенда, ставим на время задания через helm (~3 пода в ns `keda`).

## Проверка
```bash
helm repo add kedacore https://kedacore.github.io/charts >/dev/null; helm repo update kedacore >/dev/null
helm upgrade --install keda kedacore/keda -n keda --create-namespace --wait --timeout 5m
kubectl -n lab apply -f manifests/keda/cron-scaledobject.yaml
kubectl -n lab get scaledobject worker-cron
kubectl -n lab get hpa
kubectl -n lab get deploy keda-worker -w
```
Смотрите 3–4 минуты: `READY` должен ходить `0/0 → 2/2 → 0/0 → 2/2`. Затем:
```bash
kubectl -n lab describe scaledobject worker-cron | grep -A6 '^Status'
kubectl -n lab get hpa keda-hpa-worker-cron -o jsonpath='{.spec.minReplicas} {.spec.maxReplicas}{"\n"}'
```
Уборка:
```bash
kubectl -n lab delete -f manifests/keda/cron-scaledobject.yaml
helm uninstall keda -n keda; kubectl delete ns keda
```

## Ожидаемый результат
- `ScaledObject` в `READY True`, `ACTIVE` меняется вместе с окном cron; KEDA сам создал
  HPA `keda-hpa-worker-cron` с `minReplicas: 1` — потому что ниже 1 HPA не умеет, ноль
  делает **сам KEDA**, временно «отключая» HPA.
- В окне активности реплик 2 (значение `desiredReplicas`), вне окна — 0; переход вниз
  происходит не мгновенно, а после `cooldownPeriod` (30 с).
- Вы объяснили, чем KEDA отличается от HPA (внешние источники метрик, scale-to-zero,
  активация) и когда вместо `cron` взять `prometheus`-триггер из
  `manifests/keda-scaledobject.yaml` или триггер очереди (RabbitMQ/Kafka/SQS).
