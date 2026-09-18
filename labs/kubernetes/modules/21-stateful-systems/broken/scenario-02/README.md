# Сценарий 02: Приложение подключается к БД, а записи не проходят

## Симптом

Кластер `my-db` здоров, пароль верный, соединение устанавливается — но писать не выходит:

```bash
kubectl -n lab logs deploy/db-writer --tail=3
# ERROR:  cannot execute CREATE TABLE in a read-only transaction
# write failed
```

## Запуск

```bash
kubectl apply -f manifests/cluster.yaml
kubectl -n lab wait --for=condition=Ready cluster/my-db --timeout=300s
kubectl -n lab apply -f broken/scenario-02/db-writer.yaml
sleep 15; kubectl -n lab logs deploy/db-writer --tail=3
```

## Задание

1. Объясните, почему PostgreSQL отвечает «read-only transaction», если это не ошибка прав.
2. Найдите, к какому Service подключается приложение и куда этот Service ведёт.
3. Исправьте подключение, не трогая кластер БД.

Начните:

```bash
kubectl -n lab get deploy db-writer -o jsonpath='{.spec.template.spec.containers[0].args[0]}' | grep -o '\-h [a-z-]*'
kubectl -n lab get endpointslices -l kubernetes.io/service-name=my-db-ro -o jsonpath='{.items[*].endpoints[*].targetRef.name}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

CloudNativePG создаёт три Service: `-rw` → только primary, `-ro` → только реплики, `-r` → все. Реплика PostgreSQL принимает **только чтение**.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Приложение ходит в `my-db-ro`. Любая запись (DDL или INSERT) на реплике отвечает `cannot execute ... in a read-only transaction`.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Приложение подключено к `my-db-ro` — Service, который ведёт на реплику (hot standby).
  Streaming-реплика в PostgreSQL открыта только на чтение.
- Симптом легко спутать с RBAC/GRANT-ошибкой, но текст другой: не «permission denied»,
  а «read-only transaction».
- Правило маршрутизации: запись — только через `-rw`; чтение можно раскидать через `-ro`
  (`-r` — если чтение с primary допустимо). После failover `-rw` сам переезжает на нового
  primary — приложению ничего менять не нужно.

</details>

<details>
<summary><strong>Решение</strong></summary>

Ходить за записью в `my-db-rw` — `solutions/scenario-02/db-writer.yaml`:

```bash
kubectl -n lab apply -f solutions/scenario-02/db-writer.yaml
sleep 15; kubectl -n lab logs deploy/db-writer --tail=2      # inserted
kubectl -n lab delete deploy db-writer                          # уборка
```

</details>
