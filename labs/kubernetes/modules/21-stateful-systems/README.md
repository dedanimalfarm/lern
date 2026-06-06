# Лабораторная работа 21: Базы данных и Stateful-системы (CloudNativePG)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Развёртывание PostgreSQL кластера](#-1--postgresql-)
- [Часть 2: Failover (Переключение мастера)](#-2-failover--)
- [Часть 3: Бэкапы и Восстановление (ScheduledBackup)](#-3----scheduledbackup)
- [Часть 4: Rolling Upgrade (Обновление версии)](#-4-rolling-upgrade--)
- [Архитектура: CloudNativePG Operator vs StatefulSet](#-cloudnativepg-operator-vs-statefulset)
- [Практические задания](#-)
- [Финальная карта ресурсов модуля](#---)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->

> ⏱ время ~35 мин · сложность 4/5 · пререквизиты: Трек 1 и Трек 3

В этом модуле мы изучим работу с базами данных в Kubernetes на примере оператора CloudNativePG. Вы научитесь разворачивать высокодоступный кластер PostgreSQL с автоматическим failover, создавать резервные копии и выполнять бесшовные обновления (Rolling Upgrade).

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
```

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

## Часть 1: Развёртывание PostgreSQL кластера

Мы установим CloudNativePG оператор с помощью стартового скрипта:
```bash
verify/prepare.sh
```

Затем разверните кластер PostgreSQL (`Cluster` CRD) и тестовое приложение:
```bash
kubectl apply -f manifests/cluster.yaml
kubectl apply -f manifests/app.yaml
```

Проверьте статус кластера (подождите около минуты, пока поды не перейдут в статус Running):
```bash
kubectl -n lab get cluster my-db
kubectl -n lab get pods -l cnpg.io/cluster=my-db
```
Вы увидите 2 пода (один Primary, один Replica).

Подключимся к базе (пароль находится в секрете `my-db-app`):
```bash
# Тестовое приложение уже использует эти креды. Посмотрим его логи:
kubectl -n lab logs -l app=db-client
```

## Часть 2: Failover (Переключение мастера)

Оператор автоматически обрабатывает сбои. Сымитируйте падение Primary узла:
```bash
# 1. Узнаем текущий Primary:
PRIMARY_POD=$(kubectl -n lab get cluster my-db -o=jsonpath='{.status.currentPrimary}')
echo "Current Primary is: $PRIMARY_POD"

# 2. Удалим под Primary (как будто нода упала):
kubectl -n lab delete pod $PRIMARY_POD
```

Сразу же понаблюдайте за кластером:
```bash
kubectl -n lab get cluster my-db
```
Посмотрите, как быстро оператор назначит реплику новым Primary и создаст новый под для восстановления кворума.

## Часть 3: Бэкапы и Восстановление (ScheduledBackup)

Настроим автоматическое резервное копирование по расписанию:
```bash
kubectl apply -f manifests/backup.yaml
```

Посмотрите статус бэкапов:
```bash
kubectl -n lab get scheduledbackup
```

В реальной жизни бэкапы отправляются в S3 (объектное хранилище). В случае аварии, вы можете создать новый кластер из бэкапа, добавив в манифест нового кластера секцию `bootstrap: recovery`.

## Часть 4: Rolling Upgrade (Обновление версии)

CloudNativePG позволяет обновлять PostgreSQL без даунтайма.
Обновим версию образа в манифесте кластера (например, с `15.3` на `15.4` или просто изменим конфигурацию).

Отредактируйте `manifests/cluster.yaml`, увеличив количество инстансов с 2 до 3:
```bash
sed -i 's/instances: 2/instances: 3/g' manifests/cluster.yaml
kubectl apply -f manifests/cluster.yaml
```

Понаблюдайте за тем, как оператор разворачивает новую реплику:
```bash
kubectl -n lab get cluster my-db
```

## Архитектура: CloudNativePG Operator vs StatefulSet

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
│  instances: 3         │          │   [Pod: my-db-1 (Primary)]        │
│  storage: 1Gi         │          │   ├── PVC: 1Gi                    │
└───────────────────────┘          │   └── Service: my-db-rw           │
                                   │           ▲ (replication)         │
                                   │           │                       │
                                   │   [Pod: my-db-2 (Replica)]        │
                                   │   ├── PVC: 1Gi                    │
                                   │   └── Service: my-db-ro           │
                                   └───────────────────────────────────┘
```

**StatefulSet vs Operator:**
В модуле 05 мы деплоили StatefulSet вручную. Оператор (CRD + Controller) автоматизирует "человеческие" задачи DBA:
1. **Bootstrap**: Создание пользователей, баз данных, инициализация.
2. **High Availability (Failover)**: Автоматическое переключение на реплику при падении primary (StatefulSet этого не умеет, он просто пересоздаст под).
3. **Backup/Restore**: Автоматические бэкапы в S3 через pgBackRest/Barman.
4. **Upgrades**: Безопасное обновление версий PostgreSQL без простоя.

## Практические задания

1. **Trigger Manual Backup**: Изучите CRD `Backup`. Создайте манифест `Backup` (не `ScheduledBackup`), чтобы запустить резервное копирование прямо сейчас.
2. **Scale Down**: Измените количество инстансов в кластере обратно на 2.

## Финальная карта ресурсов модуля

| Ресурс | Тип | Роль |
|--------|-----|------|
| `my-db` | Cluster (CRD) | Декларативное описание желаемого кластера PostgreSQL |
| `my-db-backup` | ScheduledBackup | Расписание создания резервных копий |
| `my-db-1`, `my-db-2` | Pods | Поды инстансов БД. Управляются оператором, а не StatefulSet. |
| `my-db-rw`, `my-db-ro`| Service | `rw` маршрутизирует трафик только на Primary; `ro` балансирует запросы на чтение между Replica. |
| `db-client` | Deployment | Тестовое приложение, которое читает секрет и пишет в БД. |

## Чему вы научились

В этом модуле вы научились:
- Разворачивать PostgreSQL с помощью оператора CloudNativePG.
- Выполнять Failover и проверять устойчивость кластера БД к сбоям нод.
- Понимать разницу между базовым StatefulSet и умным Operator'ом.
- Настраивать резервное копирование и масштабировать кластер БД.

## Уборка

Очистите ресурсы после завершения:
```bash
../../scripts/clean/clean-module.sh modules/21-stateful-systems
```
