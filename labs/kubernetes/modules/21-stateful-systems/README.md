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

---

## Архитектура: CloudNativePG Operator

```text
┌───────────────────────┐          ┌───────────────────────────────────┐
│  Kubernetes API       │          │   CloudNativePG Operator          │
│                       │          │   (Deployment)                    │
│  - CRD: Cluster       │◄─────────┤   - Смотрит за ресурсами Cluster  │
│  - CRD: Backup        │          │   - Управляет Pods, PVC, Secrets  │
└──────────┬────────────┘          └────────────────┬──────────────────┘
           │                                        │
           ▼                                        ▼
┌───────────────────────┐          ┌───────────────────────────────────┐
│  CR: Cluster "my-db"  │          │   PostgreSQL Cluster (my-db)      │
│                       │          │                                   │
│  instances: 2         │          │   [Pod: my-db-1 (Primary)]        │
│  storage: 1Gi         │          │   ├── PVC: 1Gi                    │
└───────────────────────┘          │   └── Service: my-db-rw           │
                                   │           ▲ (replication)         │
                                   │           │                       │
                                   │   [Pod: my-db-2 (Replica)]        │
                                   │   ├── PVC: 1Gi                    │
                                   │   └── Service: my-db-ro           │
                                   └───────────────────────────────────┘
```

**Преимущества паттерна Operator для БД:**
Вместо того, чтобы полагаться только на базовые примитивы Kubernetes (StatefulSet + PVC), оператор внедряет **domain-specific knowledge** (знания администратора БД) прямо в кластер. Например, он знает, что для добавления реплики нужно сделать `pg_basebackup` с Primary, а при сбое — выполнить promotion реплики и обновить Service `my-db-rw`.

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Роль |
|--------|-----|------|
| `my-db` | Cluster (CRD) | Декларативное описание желаемого кластера PostgreSQL |
| `my-db-1`, `my-db-2` | Pods | Поды инстансов БД (Primary и Replica). Имена фиксированы, но управляются оператором, а не StatefulSet. |
| `my-db-rw`, `my-db-ro`| Service | `rw` маршрутизирует трафик только на Primary; `ro` балансирует запросы на чтение между Replica. |
| `my-db-app` | Secret | Автоматически сгенерированный секрет с паролем для пользователя приложения (`appuser`). |
| `db-client` | Deployment | Тестовое приложение (pgbench), которое читает секрет и пишет в БД через сервис `my-db-rw`. |

---

## Теоретические вопросы (итоговые)

1. Чем подход на базе Operator (CloudNativePG) отличается от классического StatefulSet для запуска баз данных?
2. Как тестовое приложение понимает, на какой узел (Pod) отправлять запросы `INSERT/UPDATE`, чтобы не получить ошибку "read-only transaction"?
3. Что произойдет с данными, если удалить `Cluster` my-db? Сохранятся ли PVC?
4. Зачем оператору требуется отдельная ServiceAccount с широкими правами в кластере (RBAC)?


## Чему вы научились

В этом модуле вы научились:
- Управлению базами данных с помощью операторов (CloudNativePG)
- Разнице между оператором и ручным StatefulSet
- Механизмам Failover и High Availability в БД на Kubernetes

## Уборка

Очистите ресурсы после завершения:
```bash
../../scripts/clean/clean-module.sh modules/21-stateful-systems
```
