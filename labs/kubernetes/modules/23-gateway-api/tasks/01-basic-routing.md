# 01 — Gateway + HTTPRoute: базовый маршрут

## Задача
Поднять Gateway на классе `eg`, привязать к нему HTTPRoute для `/store` и получить ответ
приложения через шлюз. Проверки — из пода внутри кластера: внутренние IP нод с рабочей
машины недостижимы.

## Проверка
```bash
kubectl apply -f manifests/01-basic-routing/
kubectl -n lab-gateway wait --for=condition=Programmed gateway/demo-gateway --timeout=120s
kubectl -n lab-gateway get gateway demo-gateway
kubectl -n lab-gateway get httproute store-route \
  -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {end}{"\n"}'
GW=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway -o jsonpath='{.items[0].metadata.name}')
kubectl -n lab-gateway run curl --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- sh -c \
  "curl -s http://$GW.envoy-gateway-system/store; echo; curl -s -o /dev/null -w '%{http_code}\n' http://$GW.envoy-gateway-system/unknown"
```

## Ожидаемый результат
- Gateway `PROGRAMMED True`; у HTTPRoute `Accepted=True ResolvedRefs=True`.
- `curl /store` → `Store V1`; `/unknown` → `404` — его отдаёт сам Envoy: маршрута нет.
- Вы показали, какой Service в `envoy-gateway-system` создал контроллер для этого Gateway
  и почему у него тип NodePort (data-plane на стенде без облачного LoadBalancer).
