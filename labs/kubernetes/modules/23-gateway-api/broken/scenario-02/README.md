# Сценарий 02: HTTPRoute Accepted: False — опечатка в parentRefs

## Симптом
```bash
kubectl apply -f broken/scenario-02/httproute.yaml
kubectl -n lab-gateway get httproute broken-route
# NAME           HOSTNAMES   AGE
# broken-route               5s     <- объект создан, но трафик на /store через него не идёт
```

## Подсказки
1. К какому Gateway привязан маршрут (`spec.parentRefs`)? Существует ли он в этом namespace?
2. Условие `Accepted` в `status.parents[].conditions` — что в `reason` и `message`?

## Диагностика
```bash
kubectl -n lab-gateway describe httproute broken-route | grep -A6 'Conditions'
# Type: Accepted / Status: False
# Reason: InvalidParentRef   (в некоторых версиях: NoMatchingParent)
# Message: Gateway "typo-gateway" not found
kubectl -n lab-gateway get gateway
# NAME           CLASS   ...   <- есть demo-gateway, typo-gateway нет
```

## Решение
Исправить имя шлюза в `parentRefs` (`solutions/scenario-02/httproute.yaml`):
```bash
kubectl apply -f solutions/scenario-02/httproute.yaml
kubectl -n lab-gateway get httproute broken-route \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'; echo
# True
kubectl delete -f solutions/scenario-02/httproute.yaml
```

## Профилактика
- Маршрут-«сирота» не ломает ничего, кроме себя — поэтому его легко не заметить. Мониторить
  `Accepted=False` у всех HTTPRoute (kube-state-metrics + алерт).
- Имена Gateway задавать через общую переменную/kustomize, а не руками в каждом маршруте.
