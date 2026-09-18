# Сценарий 03: маршрут принят, а трафик отдаёт 500/503

## Симптом
```bash
kubectl apply -f manifests/01-basic-routing/
kubectl apply -f broken/scenario-03/httproute.yaml
GW=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway -o jsonpath='{.items[0].metadata.name}')
kubectl -n lab-gateway run curl --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://$GW.envoy-gateway-system/broken-path
# 500 (по спецификации Gateway API) или 503 «no healthy upstream» — не 404: маршрут есть
kubectl -n lab-gateway get gateway demo-gateway
# NAME           CLASS   ADDRESS   PROGRAMMED   AGE
# demo-gateway   eg      ...       True         1m    <- шлюз здоров
```

## Подсказки
1. 404 отдаёт Envoy, когда маршрута нет. Что означает 500/503, если маршрут есть?
2. У HTTPRoute несколько условий в `status.parents[].conditions` — какие из них `True`,
   а какие нет? Прочитайте `reason` у того, что `False`.
3. На что указывает `backendRefs`? Существует ли такой Service в `lab-gateway`?

## Диагностика
```bash
kubectl -n lab-gateway get httproute broken-endpoints-route \
  -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} ({.reason}){"\n"}{end}'
# Accepted=True (Accepted)              <- Gateway маршрут принял
# ResolvedRefs=False (BackendNotFound)  <- а backend разрешить не смог
kubectl -n lab-gateway get httproute broken-endpoints-route -o jsonpath='{.spec.rules[0].backendRefs[0].name}{"\n"}'
# missing-service
kubectl -n lab-gateway get svc missing-service
# Error from server (NotFound): services "missing-service" not found
```

## Решение
`backendRefs` ссылается на несуществующий Service `missing-service`. По спецификации Gateway API
правило с неразрешённым backend не удаляется, а начинает отвечать `500` (Envoy Gateway некоторых
версий отдаёт `503 no healthy upstream`) — поэтому шлюз «здоров», маршрут «принят», а трафик ломается.
```bash
kubectl apply -f solutions/scenario-03/httproute.yaml
kubectl -n lab-gateway get httproute broken-endpoints-route \
  -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status}{"\n"}{end}'
# Accepted=True
# ResolvedRefs=True
kubectl -n lab-gateway run curl --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl -s http://$GW.envoy-gateway-system/broken-path
# Store V1
kubectl delete -f solutions/scenario-03/httproute.yaml
```

## Профилактика
- Смотреть не только `PROGRAMMED` у Gateway, но и **оба** условия у HTTPRoute:
  `Accepted` (привязка к Gateway) и `ResolvedRefs` (backend существует и порт найден).
- В CI гонять `kubectl wait --for=jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}'=True httproute/<name>`
  после apply.
- Различать коды шлюза: `404` — нет маршрута, `500` — маршрут есть, backend не разрешён,
  `503` — backend разрешён, но нет живых endpoints (или, в зависимости от версии, тот же неразрешённый backend).
