# Сценарий 01: База данных не может запуститься (PVC Pending)

## Симптом

Кластер PostgreSQL создан, но поды не появляются или висят в состоянии Pending долгое время.

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
```

## Стартовая проверка

Убедитесь, что кластер доступен и CloudNativePG установлен:
```bash
kubectl get nodes
```

## Запуск

```bash
kubectl apply -k broken/scenario-01
```

## Задание

1. Посмотрите статус кластера БД и PVC.
2. Выясните, почему PVC не может связаться с PersistentVolume.
3. Исправьте конфигурацию `Cluster`.

Начните диагностику:
```bash
kubectl -n lab get cluster my-db
kubectl -n lab get pvc
kubectl -n lab describe pvc my-db-1
```

<details>
<summary><strong>Подсказка</strong></summary>

В событиях (Events) объекта PVC вы увидите ошибку, связанную со `storageclass.storage.k8s.io "fast-ssd" not found`.
</details>

<details>
<summary><strong>Объяснение</strong></summary>

В манифесте указан несуществующий StorageClass `fast-ssd`. Kubernetes не может динамически создать PersistentVolume, поэтому PVC остаётся в статусе Pending. Поскольку под базы данных ожидает монтирования диска, он также не может запуститься.
</details>

<details>
<summary><strong>Решение</strong></summary>

Удалите неверный кластер и создайте правильный без указания кастомного StorageClass (будет использован дефолтный `local-path`):
```bash
kubectl -n lab delete cluster my-db
kubectl apply -f manifests/cluster.yaml
```
</details>

## Уборка

Очистите ресурсы после завершения:
```bash
../../scripts/clean/clean-module.sh modules/21-stateful-systems
```
