# Задание 2: Метрики из логов

Мгновенные запросы — через эндпоинт `/loki/api/v1/query`:

```bash
li() {
  local enc; enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1")
  kubectl -n lab exec deploy/loki -- wget -qO- "http://localhost:3100/loki/api/v1/query?query=${enc}"
}
```

1. Посчитайте интенсивность логов по уровням:
   `sum by (level) (rate({app="payment-api"} | json | __error__="" [5m]))`.
   Уберите `| __error__=""` и объясните ошибку HTTP 400, которую вернёт Loki.
2. Доля ошибок (error rate) в процентах: отношение `rate` строк со
   `status=500` к `rate` всех строк payment-api. (Подсказка: два выражения
   можно делить друг на друга прямо в LogQL.)
3. p50/p95/p99 `duration_ms` через `unwrap` + `quantile_over_time ... by (path)`.
   Почему без `by (path)` получается десяток серий?
4. Найдите самого «болтливого» производителя логов в `lab`:
   `bytes_over_time` по `app` за 15 минут.
5. Сформулируйте алерт «больше 30 ERROR-строк за 5 минут» как LogQL-выражение
   (то, что вы положили бы в Grafana Alerting).

<details><summary>Подсказка к п.2</summary>

```logql
  sum(rate({app="payment-api"} | json | __error__="" | status=500 [5m]))
/ sum(rate({app="payment-api"} | json | __error__="" [5m])) * 100
```
~15% — заложено генератором (см. manifests/app.yaml).
</details>
