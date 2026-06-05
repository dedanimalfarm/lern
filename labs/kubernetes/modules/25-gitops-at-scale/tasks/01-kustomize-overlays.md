# 01 — Kustomize base + overlays

## Задача
Понять, как один `base` превращается в три разных окружения БЕЗ копипасты —
отрендерить overlays и сравнить, что именно изменил каждый.

## Проверка
```bash
# Рендер каждого окружения (без применения в кластер):
for e in dev staging prod; do
  echo "== $e =="
  kubectl kustomize overlays/$e | grep -E 'namespace:|replicas:|image:|env:'
done
# dev:     namespace lab-dev,     replicas 1, image nginx:1.27-alpine
# staging: namespace lab-staging, replicas 2
# prod:    namespace lab-prod,    replicas 3, image nginx:1.27.3-alpine (пин)

# Применить ОДНО окружение напрямую (без Argo) — kustomize встроен в kubectl:
kubectl apply -k overlays/dev
kubectl -n lab-dev get deploy web
kubectl delete -k overlays/dev
```

## Ожидаемый результат
Три окружения из одного base; различия — только в overlay-патчах
(replicas/namespace/образ/метка `env`).
