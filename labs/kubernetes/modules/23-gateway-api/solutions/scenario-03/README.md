# Решение сценария 03

Причина: `spec.rules[0].backendRefs[0].name` указывал на несуществующий Service `missing-service`.
HTTPRoute при этом остаётся `Accepted=True`, но получает `ResolvedRefs=False`
(`reason: BackendNotFound`), и Envoy отвечает на такой маршрут `500` (или `503`).

Исправление — вернуть ссылку на реальный Service (`httproute.yaml`):

```bash
kubectl apply -f solutions/scenario-03/httproute.yaml
kubectl -n lab-gateway wait --timeout=60s httproute/broken-endpoints-route \
  --for=jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}'=True
```

Разбор шагов и профилактика — в `broken/scenario-03/README.md`.
