# 03-autoinstrument-app

## Задача
Развернуть два Python-сервиса с автоинструментацией (`opentelemetry-instrument`)
и убедиться, что запрос frontend→backend рождает ОДИН распределённый trace
из 4 спанов (SERVER → CLIENT → SERVER → INTERNAL).

## Команды
```bash
kubectl apply -f manifests/backend.yaml -f manifests/frontend.yaml -f manifests/loadgen.yaml
kubectl -n lab rollout status deploy/backend --timeout=360s    # pip ставит зависимости
kubectl -n lab rollout status deploy/frontend --timeout=360s

# Дёрнуть руками и найти трейс:
kubectl -n lab exec deploy/frontend -- wget -qO- http://localhost:5000/
sleep 10
kubectl -n lab exec deploy/frontend -- wget -qO- \
  'http://tempo:3200/api/search?q=%7Bresource.service.name%3D%22frontend%22%7D&limit=1'
# взять traceID из ответа и раскрыть весь трейс:
kubectl -n lab exec deploy/frontend -- wget -qO- 'http://tempo:3200/api/traces/<TRACEID>'
```

## Проверка
- В одном traceID 4 спана двух сервисов: `GET /` (frontend, SERVER) →
  `GET` (frontend, CLIENT) → `GET /api/quote` (backend, SERVER) →
  `db-query` (backend, INTERNAL, ручной).
- TraceQL `{status=error}` находит трейсы симулированных ошибок backend (~10%).

## Вопросы
1. Какой заголовок переносит trace-контекст между сервисами и кто его ставит?
2. Чем спан вида CLIENT отличается от SERVER в этом трейсе?
3. Зачем в коде backend ручной спан, если Flask и так инструментирован?
