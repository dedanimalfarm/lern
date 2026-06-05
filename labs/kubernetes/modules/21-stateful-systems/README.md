# Лабораторная работа 21: Базы данных и Stateful-системы (CloudNativePG)
> ⏱ время ~35 мин · сложность 4/5 · пререквизиты: Трек 1 и Трек 3

В этом модуле мы изучим работу с базами данных в Kubernetes на примере оператора CloudNativePG. Вы научитесь разворачивать высокодоступный кластер PostgreSQL с автоматическим failover и создавать резервные копии.

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
```

## Стартовая проверка

Убедитесь, что кластер доступен и оператор установлен:
```bash
kubectl get nodes
```

## 1. Развёртывание PostgreSQL кластера

Мы установим CloudNativePG оператор с помощью стартового скрипта:
```bash
verify/prepare.sh
```

Затем разверните кластер PostgreSQL (`Cluster` CRD) и тестовое приложение:
```bash
kubectl apply -f manifests/cluster.yaml
kubectl apply -f manifests/app.yaml
```

Проверьте статус кластера:
```bash
kubectl -n lab get cluster my-db
kubectl -n lab get pods -l cnpg.io/cluster=my-db
```

Вы увидите 2 пода (один Primary, один Replica).

## 2. Оператор vs Ручной StatefulSet

В модуле 05 мы деплоили StatefulSet вручную. Оператор (CRD + Controller) автоматизирует "человеческие" задачи DBA:
1. **Bootstrap**: Создание пользователей, баз данных, инициализация.
2. **High Availability**: Автоматический failover (переключение на реплику при падении primary).
3. **Backup/Restore**: Автоматические бэкапы через pgBackRest/Barman.
4. **Upgrades**: Безопасное обновление версий PostgreSQL без простоя.

## Практические задания

### Задание 1. Подключение к БД
Оператор автоматически создал Service `my-db-rw` для чтения/записи (направляет на Primary) и `my-db-ro` для чтения (направляет на Replica). Подключимся к базе (пароль находится в секрете `my-db-app`):
```bash
# Тестовое приложение уже использует эти креды. Посмотрим его логи:
kubectl -n lab logs -l app=db-client
```

### Задание 2. Failover (Переключение мастера)
Сымитируйте падение Primary узла:
```bash
# Узнаем текущий Primary:
kubectl -n lab get cluster my-db -o=jsonpath='{.status.currentPrimary}'

# Удалим под Primary (как будто нода упала):
kubectl -n lab delete pod my-db-1
```
Посмотрите, как быстро оператор назначит реплику `my-db-2` новым Primary и создаст новый под для восстановления кворума.

## Уборка

Очистите ресурсы после завершения:
```bash
../../scripts/clean/clean-module.sh modules/21-stateful-systems
```
