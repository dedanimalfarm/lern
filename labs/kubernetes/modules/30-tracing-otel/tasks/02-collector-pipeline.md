# 02-collector-pipeline

## Задача
Поставить OTel Collector между источником спанов и Tempo. Прочитать его конфиг
как пайплайн: receivers → processors → exporters.

## Команды
```bash
kubectl apply -f manifests/otel-collector.yaml
kubectl -n lab rollout status deploy/otel-collector --timeout=120s

# Тот же telemetrygen, но endpoint теперь коллектор:
kubectl create -f extras/telemetrygen-via-collector.yaml
kubectl -n lab wait --for=condition=complete job/telemetrygen-via-collector --timeout=120s

# debug exporter печатает каждый батч (доказательство «спаны дошли до коллектора»):
kubectl -n lab logs deploy/otel-collector --tail=20 | grep -A2 TracesExporter
```

## Проверка
- В логах коллектора видны строки debug-экспортёра с количеством спанов.
- TraceQL `{resource.service.name="telemetrygen-collector"}` находит трейсы.

## Вопросы
1. Зачем `memory_limiter` ставят первым процессором пайплайна?
2. Почему приложения должны знать адрес коллектора, а не бэкенда (Tempo)?
3. Коллектор перечитывает ConfigMap на лету?  (нет — только при старте)
