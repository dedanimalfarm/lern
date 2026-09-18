# 03 — Canary через веса backendRefs

## Задача
Развернуть `store-v2`, разделить трафик 90/10 и увидеть распределение; затем перевести
100 % на v2 без пересоздания маршрута.

## Проверка
```bash
kubectl apply -f manifests/02-traffic-splitting/
GW=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway -o jsonpath='{.items[0].metadata.name}')
kubectl -n lab-gateway run curl --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- sh -c \
  "for i in \$(seq 1 50); do curl -s http://$GW.envoy-gateway-system/store; echo; done | sort | uniq -c"
kubectl -n lab-gateway patch httproute store-route --type=json \
  -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":0},{"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":100}]'
kubectl -n lab-gateway run curl --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- sh -c \
  "for i in \$(seq 1 20); do curl -s http://$GW.envoy-gateway-system/store; echo; done | sort | uniq -c"
```

## Ожидаемый результат
- Первый прогон: порядка `45 Store V1 / 5 Store V2` — на малой выборке разброс нормален,
  Envoy делит трафик вероятностно.
- После патча весов — только `Store V2`.
- Вы объяснили, чем это отличается от canary в Argo Rollouts (модуль 24): здесь нет
  анализа метрик и автоотката — только распределение, решение о promote принимает человек.
