# 01 — Bootstrap кластера CNPG и маршрутизация подключений

## Задача
Развернуть кластер PostgreSQL из двух инстансов, найти Primary и Replica и доказать, что
`my-db-rw` ведёт только на Primary, а `my-db-ro` — только на реплику.

## Проверка
```bash
kubectl apply -f manifests/cluster.yaml
kubectl -n lab wait --for=condition=Ready cluster/my-db --timeout=300s
kubectl -n lab get cluster my-db
kubectl -n lab get pods -l cnpg.io/cluster=my-db -L cnpg.io/instanceRole
kubectl -n lab get svc -l cnpg.io/cluster=my-db
kubectl -n lab get endpointslices -l kubernetes.io/service-name=my-db-rw -o jsonpath='{.items[*].endpoints[*].targetRef.name}'; echo
kubectl -n lab get endpointslices -l kubernetes.io/service-name=my-db-ro -o jsonpath='{.items[*].endpoints[*].targetRef.name}'; echo
for p in my-db-1 my-db-2; do echo -n "$p: "; kubectl -n lab exec "$p" -c postgres -- psql -U postgres -tAc 'select pg_is_in_recovery();'; done
kubectl -n lab logs deploy/db-client --tail=3
```

## Ожидаемый результат
- `STATUS: Cluster in healthy state`, `READY 2`, колонка `PRIMARY` называет один под.
- В endpoint'ах `my-db-rw` ровно один под (Primary), в `my-db-ro` — второй;
  `pg_is_in_recovery()` на реплике возвращает `t`, на Primary — `f`.
- `db-client` пишет строки без `DB connection failed`.
- Вы объяснили, почему приложению нельзя ходить в под напрямую по имени и чем `my-db-r`
  отличается от `my-db-ro`.
