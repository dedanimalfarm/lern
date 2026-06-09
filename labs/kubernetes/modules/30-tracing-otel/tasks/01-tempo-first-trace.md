# 01-tempo-first-trace

## Задача
Поднять Tempo и получить в нём первый трейс — без приложений и коллектора,
синтетикой telemetrygen. Понять механику «OTLP → бэкенд → search API».

## Команды
```bash
kubectl apply -f manifests/tempo.yaml
kubectl -n lab rollout status deploy/tempo --timeout=120s

kubectl create -f extras/telemetrygen-direct.yaml
kubectl -n lab wait --for=condition=complete job/telemetrygen-direct --timeout=120s

# Поиск по TraceQL (Tempo 3.0: легаси ?tags= больше не фильтрует):
kubectl -n lab exec deploy/frontend -- wget -qO- \
  'http://tempo:3200/api/search?q=%7Bresource.service.name%3D%22telemetrygen%22%7D&limit=3'
```

## Проверка
- Job `telemetrygen-direct` — Complete.
- Search возвращает трейсы с `rootServiceName: telemetrygen`,
  `rootTraceName: lets-go`.

## Вопросы
1. На каком порту Tempo принимает OTLP/gRPC, а на каком отвечает на запросы?
2. Чем `/api/search` отличается от `/api/traces/<id>`?
