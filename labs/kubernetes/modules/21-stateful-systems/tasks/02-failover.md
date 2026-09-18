# 02 — Failover: убить Primary и наблюдать выборы

## Задача
Сымитировать падение Primary и измерить RTO: за сколько секунд кластер снова здоров и кто
стал новым Primary. Убедиться, что клиент пережил переключение, а старый Primary вернулся
репликой, а не вторым мастером.

## Проверка
```bash
OLD=$(kubectl -n lab get cluster my-db -o jsonpath='{.status.currentPrimary}'); echo "primary: $OLD"
date +%T; kubectl -n lab delete pod "$OLD" --wait=false
kubectl -n lab get cluster my-db -w
```
В другом терминале:
```bash
kubectl -n lab logs deploy/db-client -f --tail=1
```
После стабилизации:
```bash
date +%T; kubectl -n lab get cluster my-db -o jsonpath='{.status.currentPrimary}{" "}{.status.phase}{"\n"}'
kubectl -n lab get pods -l cnpg.io/cluster=my-db -L cnpg.io/instanceRole
kubectl -n lab get events --field-selector involvedObject.name=my-db --sort-by=.lastTimestamp | tail -5
```

## Ожидаемый результат
- В `-w` последовательность статусов `Failing over` → `Cluster in healthy state`;
  `currentPrimary` сменился на другой под.
- Старый под вернулся с ролью `replica` — fencing: он увидел в API нового Primary
  и не стал вторым мастером.
- `db-client` выдал несколько строк `DB connection failed` и продолжил писать — разница
  между двумя `date +%T` и есть ваш RTO (десятки секунд).
- Вы объяснили, при чём здесь Lease в Kubernetes API и почему не случился split-brain.
