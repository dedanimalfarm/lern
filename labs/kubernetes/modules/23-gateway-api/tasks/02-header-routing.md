# 02 — Маршрутизация по заголовку

## Задача
Добавить HTTPRoute, который пускает на `/beta` только запросы с заголовком
`X-Beta-Access: true`, и доказать поведение с заголовком и без.

## Проверка
```bash
kubectl apply -f manifests/03-advanced-routing/httproute-headers.yaml
kubectl -n lab-gateway get httproute header-route \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'; echo
GW=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway -o jsonpath='{.items[0].metadata.name}')
kubectl -n lab-gateway run curl --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- sh -c \
  "curl -s -o /dev/null -w 'без заголовка: %{http_code}\n' http://$GW.envoy-gateway-system/beta; \
   curl -s -H 'X-Beta-Access: true' http://$GW.envoy-gateway-system/beta; echo"
```

## Ожидаемый результат
- `Accepted=True`; без заголовка — `404` (условия `matches` не совпали), с заголовком — `Store V1`.
- Вы объяснили, что элементы массива `matches` объединяются по ИЛИ, а условия внутри
  одного элемента (path + headers) — по И, и как Envoy выбирает правило при пересечении
  двух HTTPRoute (более специфичный match побеждает, затем — более старый ресурс).
