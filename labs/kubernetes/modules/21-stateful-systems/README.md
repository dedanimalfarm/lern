# Лабораторная работа 21: Базы данных и Stateful-системы (CloudNativePG)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Часть 1: Эволюция баз данных в Kubernetes (Теория)](#часть-1-эволюция-баз-данных-в-kubernetes-теория)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью)
  - [1.1 Почему StatefulSet недостаточно](#11-почему-statefulset-недостаточно)
  - [1.2 Паттерн Operator (CRD + Controller)](#12-паттерн-operator-crd--controller)
  - [1.3 Архитектура CloudNativePG](#13-архитектура-cloudnativepg)
- [Часть 2: Развёртывание PostgreSQL кластера](#часть-2-развёртывание-postgresql-кластера)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-1)
  - [2.1 Bootstrap кластера](#21-bootstrap-кластера)
  - [2.2 Подключение к БД и маршрутизация](#22-подключение-к-бд-и-маршрутизация)
- [Часть 3: High Availability и Failover (Переключение мастера)](#часть-3-high-availability-и-failover-переключение-мастера)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-2)
  - [3.1 Имитация сбоя Primary узла](#31-имитация-сбоя-primary-узла)
  - [3.2 Кворум и предотвращение Split-Brain](#32-кворум-и-предотвращение-split-brain)
- [Часть 4: Бэкапы, Архивация WAL и Восстановление (PITR)](#часть-4-бэкапы-архивация-wal-и-восстановление-pitr)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-3)
  - [4.1 Запуск резервного копирования по расписанию](#41-запуск-резервного-копирования-по-расписанию)
  - [4.2 Point in Time Recovery (PITR)](#42-point-in-time-recovery-pitr)
- [Часть 5: Масштабирование и Rolling Upgrade (Обновление версии)](#часть-5-масштабирование-и-rolling-upgrade-обновление-версии)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-4)
  - [5.1 Scale Out (Read Replicas)](#51-scale-out-read-replicas)
  - [5.2 Обновление версии без простоя](#52-обновление-версии-без-простоя)
- [Часть 6: Управление подключениями (Connection Pooling)](#часть-6-управление-подключениями-connection-pooling)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-5)
  - [6.1 Настройка Pooler (PgBouncer)](#61-настройка-pooler-pgbouncer)
- [Часть 7: Troubleshooting — боевые инциденты](#часть-7-troubleshooting--боевые-инциденты)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-6)
  - [Инцидент 1: Под БД в `CrashLoopBackOff` (Нехватка ресурсов)](#инцидент-1-под-бд-в-crashloopbackoff-нехватка-ресурсов)
  - [Инцидент 2: Оператор упал, Failover не работает](#инцидент-2-оператор-упал-failover-не-работает)
  - [Инцидент 3: Ошибка при создании бэкапа (Креды S3)](#инцидент-3-ошибка-при-создании-бэкапа-креды-s3)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
  - [Блок 1: StatefulSet vs Operator](#блок-1-statefulset-vs-operator)
  - [Блок 2: CloudNativePG кластер](#блок-2-cloudnativepg-кластер)
  - [Блок 3: HA & Failover](#блок-3-ha--failover)
  - [Блок 4: Бэкапы и Восстановление](#блок-4-бэкапы-и-восстановление)
  - [Блок 5: Troubleshooting](#блок-5-troubleshooting)
- [Чему вы научились](#чему-вы-научились)
- [Проверка модуля](#проверка-модуля)
- [Уборка](#уборка)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
- [Решения (Solutions)](#решения-solutions)
<!-- /TOC -->


> ⏱ время ~45 мин · сложность 4/5 · пререквизиты: Трек 1 (Основы k8s) и Трек 3 (Хранилище, модуль 05)

---

Цель всей работы: понять разницу между базовыми абстракциями (StatefulSet) и специализированными Операторами на примере базы данных PostgreSQL; научиться разворачивать высокодоступный кластер (HA) с автоматическим переключением (failover), настраивать бэкапы, пул коннектов и понимать механизмы бесшовного обновления.

> Все манифесты этой работы лежат в `manifests/`, поломки — в `broken/`,
> эталонные решения — в `solutions/`, автопроверка — в `verify/verify.sh`.
> README — это полный сценарий прохождения; манифесты применяются как файлы.

---

## Предварительные требования

```bash
# Укажите kubeconfig вашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf

# 1) Проверьте, что кластер доступен и вы имеете права администратора
kubectl cluster-info
```

```text
Kubernetes control plane is running at https://192.168.1.100:6443
CoreDNS is running at https://192.168.1.100:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

```bash
kubectl get nodes
```

```text
NAME           STATUS   ROLES           AGE   VERSION
k8s-node-1     Ready    control-plane   10d   v1.36.1
k8s-node-2     Ready    <none>          10d   v1.36.1
k8s-node-3     Ready    <none>          10d   v1.36.1
```

```bash
# 2) Убедитесь, что у вас есть дефолтный StorageClass с поддержкой PersistentVolumeClaim
kubectl get storageclass
```

```text
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  10d
```

> **Важно:** Для развёртывания баз данных крайне желательно иметь StorageClass с режимом `WaitForFirstConsumer`, чтобы тома создавались в нужной зоне доступности вместе с подами БД. Если StorageClass нет, вернитесь к модулю `05-storage` и установите `local-path-provisioner`.

```bash
# 3) Создадим namespace для работы (по умолчанию мы используем `lab`)
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# Удобный алиас
alias k='kubectl -n lab'
```

---

## Стартовая проверка

```bash
# Проверим, нет ли уже запущенных баз данных от прошлых запусков
kubectl -n lab get pods -l app=postgres
# Вывод должен быть пустым

# Убедимся, что ресурсы узлов позволяют разместить как минимум 2 пода с БД
kubectl describe nodes | grep -i cpu
```

---

## Часть 1: Эволюция баз данных в Kubernetes (Теория)

### Теория для изучения перед частью

- Почему Stateful-нагрузки (БД, брокеры сообщений) долго считались "антипаттерном" в K8s
- Жизненный цикл базы данных vs жизненный цикл Stateless-приложения (Deployment)
- Разница между `Deployment` (эквивалентные реплики) и `StatefulSet` (уникальная идентичность)
- Паттерн Operator: почему одного StatefulSet недостаточно
- Как CloudNativePG (CNPG) расширяет API Kubernetes
- Архитектура CloudNativePG: Instance Manager, Primary, Replica, Streaming Replication.

### 1.1 Почему StatefulSet недостаточно

В модуле 05 вы познакомились со `StatefulSet`. Он решает базовые проблемы: дает стабильные сетевые имена (`db-0`, `db-1`) и собственные тома (`volumeClaimTemplates`). 

Но база данных (PostgreSQL) — это сложная система, которая требует человеческого вмешательства (DBA) для:
1. **Инициализации (Bootstrap):** Базу нужно создать, задать пароли, запустить скрипты миграции. `StatefulSet` просто запускает бинарник.
2. **High Availability (HA):** Если под `db-0` (Primary) падает, `StatefulSet` пересоздаст его, но на это уйдет время. Настоящий HA требует **Failover**: мгновенного повышения реплики (`db-1`) до Primary и перенаправления туда трафика.
3. **Бэкапы:** Нужно периодически запускать `pg_dump` или `pgBackRest`, выгружать WAL-файлы (Write-Ahead Logs) в S3-хранилище.
4. **Обновления:** Обновление версии БД требует аккуратного переключения реплик, а иногда логической репликации, чтобы избежать простоя.

`StatefulSet` ничего этого не умеет. Это просто "запускалка подов по порядку".

### 1.2 Паттерн Operator (CRD + Controller)

Для автоматизации работы DBA был придуман паттерн **Operator**.
Оператор = **Custom Resource Definition (CRD)** + **Custom Controller**.

- **CRD:** Расширяет Kubernetes API. Вместо манифеста `StatefulSet` вы пишете манифест `Cluster` (CRD от CloudNativePG).
- **Controller:** Программа (под), которая работает в кластере, следит за объектами `Cluster` и превращает желаемое состояние (yaml) в реальность (создаёт поды, настраивает репликацию, делает failover).

### 1.3 Архитектура CloudNativePG

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
                                   │           ▲ (streaming replication)
                                   │           │                       │
                                   │   [Pod: my-db-2 (Replica)]        │
                                   │   ├── PVC: 1Gi                    │
                                   │   └── Service: my-db-ro           │
                                   └───────────────────────────────────┘
```

Каждый под PostgreSQL в CNPG запускается вместе с легковесным бинарником **Instance Manager**, который работает как PID 1 (вместо самого postgres). Instance Manager:
- Управляет процессом postgres
- Отправляет метрики
- Сообщает о своём состоянии оператору
- Следит за WAL-архивацией.

---

## Часть 2: Развёртывание PostgreSQL кластера

### Теория для изучения перед частью

- Ресурс `Cluster` (API: `postgresql.cnpg.io/v1`)
- Автоматическая генерация сертификатов (TLS) и секретов (логин/пароль)
- Сервисы `rw`, `ro`, `r` и их различие в маршрутизации.
- InitDB параметры.

### 2.1 Bootstrap кластера

Установим сам оператор CloudNativePG. В production он ставится через Helm, здесь используем готовый скрипт с манифестами.

```bash
# Установит CRD и развернет Deployment оператора в cnpg-system
bash verify/prepare.sh

# Убедимся, что оператор работает
kubectl get pods -n cnpg-system
```

```text
NAME                                         READY   STATUS    RESTARTS   AGE
cnpg-controller-manager-6d8b9d7547-jvwkw   1/1     Running   0          45s
```

Развернём наш первый кластер БД (`manifests/cluster.yaml`):

```yaml
# manifests/cluster.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-db
  namespace: lab
spec:
  instances: 2
  storage:
    size: 1Gi
  bootstrap:
    initdb:
      database: app_db
      owner: app_user
```

```bash
# Применим манифест
kubectl apply -f manifests/cluster.yaml

# Применим тестовое приложение, которое будет писать в эту БД
kubectl apply -f manifests/app.yaml
```

Проверим создание кластера:

```bash
# CRD Cluster
kubectl -n lab get cluster my-db
```

```text
NAME    AGE   INSTANCES   READY   STATUS                     PRIMARY
my-db   1m    2           2       Cluster in healthy state   my-db-1
```

```bash
# Поды создаются по очереди (как в StatefulSet)
kubectl -n lab get pods -l cnpg.io/cluster=my-db -w
# Подождите около минуты, пока my-db-1 и my-db-2 не перейдут в Running
```

```text
NAME      READY   STATUS    RESTARTS   AGE
my-db-1   1/1     Running   0          60s
my-db-2   1/1     Running   0          30s
```

### 2.2 Подключение к БД и маршрутизация

Оператор автоматически создал **Secrets** с паролями и **Services** для маршрутизации трафика:

```bash
# Посмотрим сервисы
kubectl -n lab get svc -l cnpg.io/cluster=my-db
```

```text
NAME            TYPE        CLUSTER-IP      PORT(S)    AGE
my-db-r         ClusterIP   10.233.10.100   5432/TCP   2m
my-db-ro        ClusterIP   10.233.10.101   5432/TCP   2m
my-db-rw        ClusterIP   10.233.10.102   5432/TCP   2m
```

Вы увидите:
- `my-db-rw` — указывает **только** на Primary (чтение и запись)
- `my-db-ro` — балансирует по всем Replica (только чтение)
- `my-db-r`  — балансирует по всем подам (Primary + Replica) для чтения.

Секреты с паролями:

```bash
kubectl -n lab get secret my-db-app -o jsonpath="{.data.password}" | base64 -d; echo
```

Наше тестовое приложение уже подключено. Посмотрим логи:

```bash
kubectl -n lab logs -l app=db-client --tail=5
```

```text
2026-06-22 22:50:12: Inserted row 1 into test_table
2026-06-22 22:50:14: Inserted row 2 into test_table
2026-06-22 22:50:16: Inserted row 3 into test_table
```

---

## Часть 3: High Availability и Failover (Переключение мастера)

### Теория для изучения перед частью

- **RTO (Recovery Time Objective):** Как быстро база должна восстановить работу после сбоя (обычно секунды).
- **RPO (Recovery Point Objective):** Сколько данных мы готовы потерять (в идеале 0).
- **Split-Brain:** Ситуация, когда два узла считают себя Primary. Приводит к конфликту данных (corruption).
- **Кворум / Fencing:** Механизмы изоляции старого Primary, чтобы он гарантированно перестал принимать запись до того, как реплика станет новым Primary.

### 3.1 Имитация сбоя Primary узла

Оператор CNPG автоматически реагирует на отказы. Если нода падает (или под удаляется), оператор:
1. Выбирает самую актуальную реплику (по LSN).
2. Выполняет команду `pg_promote` на реплике, делая её Primary.
3. Переключает Service `my-db-rw` на новый под.
4. Запускает новый под взамен упавшего и настраивает его как новую реплику.

Проверим на практике:

```bash
# 1. Узнаем, какой под сейчас Primary:
PRIMARY_POD=$(kubectl -n lab get cluster my-db -o=jsonpath='{.status.currentPrimary}')
echo "Текущий Primary: $PRIMARY_POD"
# Текущий Primary: my-db-1

# 2. Посмотрим логи клиента, он стабильно пишет данные
kubectl -n lab logs -l app=db-client --tail=3

# 3. Убьём Primary (имитация падения ноды/пода)
kubectl -n lab delete pod $PRIMARY_POD
```

Сразу же запустите просмотр состояния кластера:

```bash
kubectl -n lab get cluster my-db
```

```text
NAME    AGE   INSTANCES   READY   STATUS                     PRIMARY
my-db   5m    2           1       Failing over               my-db-2
```

Через несколько секунд статус сменится на `Cluster in healthy state`.

### 3.2 Кворум и предотвращение Split-Brain

Почему не произошел Split-Brain?
Потому что Instance Manager, запущенный в каждом поде, регулярно общается с API Server Kubernetes. Когда Primary падает, его "Lease" (ресурс блокировки) истекает. Оператор видит это и безопасно назначает реплику новым Primary.
Если старый Primary восстанет из мёртвых (сетевое разделение исчезло), он увидит в Kubernetes API, что Primary уже другой, и добровольно перейдёт в статус реплики (включится fencing).

Посмотрим на новый статус подов:

```bash
kubectl -n lab get pods -l cnpg.io/cluster=my-db
```

```text
NAME      READY   STATUS    RESTARTS   AGE
my-db-1   1/1     Running   0          10s  <-- Пересоздан, теперь Replica
my-db-2   1/1     Running   0          5m   <-- Теперь Primary
```

---

## Часть 4: Бэкапы, Архивация WAL и Восстановление (PITR)

### Теория для изучения перед частью

- Разница между логическим бэкапом (`pg_dump`) и физическим (`pg_basebackup`, `Barman`).
- **WAL (Write-Ahead Log):** Журнал транзакций. Перед тем как изменить данные на диске, PostgreSQL пишет намерение в WAL.
- Архивация WAL: Непрерывная отправка WAL-файлов в S3 (или другое объектное хранилище).
- **PITR (Point-In-Time Recovery):** Восстановление на конкретную секунду. Берётся старый полный бэкап и поверх него накатываются заархивированные WAL до нужного момента времени.
- CRD `Backup` и `ScheduledBackup`.

### 4.1 Запуск резервного копирования по расписанию

Обычно конфигурация S3 прописывается в ресурсе `Cluster` в блоке `backup.barmanObjectStore`.
В нашей лабе мы используем локальный volume (pvc) для бэкапов (для упрощения), но логика та же.

Посмотрим на манифест `manifests/backup.yaml`:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: my-db-backup
  namespace: lab
spec:
  cluster:
    name: my-db
  schedule: "0 0 0 * * *" # Каждый день в полночь
  backupOwnerReference: self
```

```bash
# Применим расписание
kubectl apply -f manifests/backup.yaml

# Проверим
kubectl -n lab get scheduledbackup
```

```text
NAME           AGE   SCHEDULE      SUSPENDED   LAST BACKUP   LAST SUCCESSFUL
my-db-backup   10s   0 0 0 * * *   false       <none>        <none>
```

Вручную запустим бэкап, создав CRD `Backup` (он триггерит создание одноразового бэкапа):

```bash
cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: manual-backup
  namespace: lab
spec:
  cluster:
    name: my-db
EOF

# Посмотрим статус
kubectl -n lab get backup manual-backup
# Вы должны увидеть PHASE: completed (через секунд 10-20)
```

```text
NAME            AGE   CLUSTER   PHASE       ERROR
manual-backup   20s   my-db     completed   
```

### 4.2 Point in Time Recovery (PITR)

Если кто-то случайно выполнил `DROP TABLE users;`, вы можете развернуть НОВЫЙ кластер `Cluster`, указав в секции `bootstrap`:

```yaml
  bootstrap:
    recovery:
      source: my-db
      recoveryTarget:
        targetTime: "2026-05-30 14:00:00"
```
Оператор скачает данные из бэкапов и восстановит БД в точности до секунды.

---

## Часть 5: Масштабирование и Rolling Upgrade (Обновление версии)

### Теория для изучения перед частью

- Разница между Minor Upgrade (15.3 -> 15.4) и Major Upgrade (14 -> 15).
- Механика Rolling Upgrade: сначала обновляются реплики, затем switchover (primary -> replica), затем обновляется бывший primary. Даунтайм = время switchover (пара секунд).
- Масштабирование нагрузки на чтение (Scale Out).

### 5.1 Scale Out (Read Replicas)

Если приложению не хватает ресурсов для выполнения SELECT-запросов, мы можем добавить больше реплик.

```bash
# Отредактируем манифест или используем команду patch
kubectl -n lab patch cluster my-db --type='merge' -p '{"spec":{"instances":3}}'

# Посмотрим, как оператор разворачивает 3-ю реплику:
kubectl -n lab get cluster my-db -w
# Дождитесь, пока INSTANCES не станет 3, а READY тоже 3
```

Трафик к `my-db-ro` теперь балансируется между двумя репликами (а Primary обрабатывает только запись или чтение к `my-db-rw`).

### 5.2 Обновление версии без простоя

Обновление базового образа (например, обновление ОС или патч БД):

```bash
# Изменим image в конфигурации (в CNPG это делается через .spec.imageName)
kubectl -n lab patch cluster my-db --type='merge' -p '{"spec":{"imageName":"ghcr.io/cloudnative-pg/postgresql:15.4"}}'
```

Наблюдайте за Rolling Update:

```bash
kubectl -n lab get pods -l cnpg.io/cluster=my-db -w
```

Вы увидите, что:
1. Удаляется одна реплика. Поднимается с версией 15.4.
2. Удаляется вторая реплика. Поднимается с версией 15.4.
3. Происходит Switchover (переключение мастера на обновленную реплику).
4. Удаляется старый мастер и поднимается с 15.4.
Таким образом, кластер всегда имеет как минимум 1-2 живых ноды, и приложение почти не замечает простоя.

---

## Часть 6: Управление подключениями (Connection Pooling)

### Теория для изучения перед частью

- **PostgreSQL Connection Overhead:** Каждое соединение в Postgres — это отдельный процесс ОС (fork), потребляющий ~10 MB памяти. 1000 соединений могут "съесть" 10 GB ОЗУ.
- **PgBouncer:** Легковесный прокси-сервер, который принимает тысячи соединений от клиентов, но держит лишь несколько десятков реальных соединений к Postgres.
- CRD `Pooler` в CloudNativePG.

### 6.1 Настройка Pooler (PgBouncer)

Создадим CRD `Pooler`:

```yaml
# manifests/pooler.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: my-db-pooler
  namespace: lab
spec:
  cluster:
    name: my-db
  instances: 2
  type: rw
  pgbouncer:
    poolMode: transaction
```

```bash
kubectl apply -f manifests/pooler.yaml

# Убедимся, что поды PgBouncer запустились
kubectl -n lab get pods -l cnpg.io/poolerName=my-db-pooler
```

Приложение теперь должно подключаться к Service `my-db-pooler` вместо `my-db-rw`. Это кардинально снизит потребление памяти на стороне БД при пиковых нагрузках (например, "шторм переподключений" при рестарте микросервисов).

---

## Часть 7: Troubleshooting — боевые инциденты

### Теория для изучения перед частью

- Команды диагностики: `kubectl logs`, `kubectl describe`, events кластера.
- Почему под с БД уходит в `CrashLoopBackOff` (Чаще всего — OOMKilled, неверная конфигурация `postgresql.conf`, поврежденный WAL).
- Как архитектура CNPG помогает избежать большинства проблем (оператор не даст применить плохой конфиг).

### Инцидент 1: Под БД в `CrashLoopBackOff` (Нехватка ресурсов)

**Симптом:**
```bash
kubectl -n lab get pods
# my-db-1   0/1   CrashLoopBackOff   ...
```

**Диагностика:**
1. Описание пода: `kubectl -n lab describe pod my-db-1 | grep -A5 Events` (ищем OOMKilled или FailedScheduling из-за нехватки CPU/RAM).
2. Логи Instance Manager: `kubectl -n lab logs my-db-1` (ошибки парсинга конфига, ошибки запуска `postgres`).

**Решение:**
Измените `.spec.resources` в манифесте `Cluster`. Оператор перезапустит поды с новыми лимитами.

### Инцидент 2: Оператор упал, Failover не работает

**Симптом:**
Primary нода упала, но реплика не становится новым Primary. `Target Primary` в выводе `kubectl get cluster` не меняется.

**Диагностика:**
Проверьте статус пода оператора:
```bash
kubectl get pods -n cnpg-system
# cnpg-controller-manager-...   0/1   Error
```

**Решение:**
Если оператор упал (например, его вытеснил другой под), Kubernetes не сможет выполнять failover. Посмотрите логи оператора: `kubectl logs -n cnpg-system deploy/cnpg-controller-manager`. После того как оператор перезапустится, кластер починит себя сам. *База данных продолжает работать на чтение (через реплики), даже если оператор мёртв!*

### Инцидент 3: Ошибка при создании бэкапа (Креды S3)

**Симптом:**
```bash
kubectl -n lab get backup
# manual-backup   failed
```

**Диагностика:**
`kubectl -n lab describe backup manual-backup` покажет Event: `Error during backup... S3 Access Denied`.

**Решение:**
Убедитесь, что Secret с `AWS_ACCESS_KEY_ID` указан корректно и находится в том же Namespace, что и кластер.

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Роль |
|--------|-----|------|
| `my-db` | Cluster (CRD) | Декларативное описание желаемого кластера PostgreSQL |
| `my-db-pooler` | Pooler (CRD) | Инстансы PgBouncer для эффективного пула соединений |
| `my-db-backup` | ScheduledBackup | Расписание создания резервных копий (бэкапов) |
| `my-db-1`, `2`, `3` | Pods | Поды инстансов БД. Управляются оператором, а не StatefulSet. |
| `my-db-rw`, `ro`, `r`| Service | `rw` (Primary); `ro` (Replica); `r` (Primary + Replica). |
| `db-client` | Deployment | Тестовое приложение, которое читает секрет и пишет в БД. |

---

## Теоретические вопросы (итоговые)

### Блок 1: StatefulSet vs Operator
1. В чём ключевое архитектурное отличие деплоя базы данных через Operator по сравнению со стандартным Kubernetes StatefulSet?
2. Какие человеческие задачи (DBA) берет на себя оператор?

### Блок 2: CloudNativePG кластер
3. Зачем CloudNativePG запускает бинарник `Instance Manager` (PID 1) вместо самого процесса `postgres`?
4. Какие Services автоматически создаются для маршрутизации трафика и в чем разница между `rw` и `ro`?

### Блок 3: HA & Failover
5. Почему для баз данных важно использовать механизмы обеспечения кворума? Как CNPG решает проблему Split-Brain?
6. Что произойдет с кластером PostgreSQL, если удалить под с самим оператором `cnpg-controller-manager`? Перестанет ли БД отвечать на запросы?

### Блок 4: Бэкапы и Восстановление
7. В чём разница между CRD `Backup` и `ScheduledBackup`?
8. Зачем в ресурсе `Cluster` используется параметр `bootstrap: recovery`, и в каких сценариях он применяется (что такое PITR)?

### Блок 5: Troubleshooting
9. Если под БД уходит в `CrashLoopBackOff`, какую команду вы используете первой для диагностики?
10. Почему добавление PgBouncer (ресурс `Pooler`) спасает кластер от Out-Of-Memory ошибок при большом количестве микросервисов?

---

## Чему вы научились

В этом модуле вы научились:
- Разворачивать PostgreSQL кластер с помощью мощного оператора CloudNativePG.
- Понимать пропасть между "просто запустить БД в Docker/StatefulSet" и "HA Database в Kubernetes".
- Выполнять Failover и проверять устойчивость кластера БД к сбоям нод (Split-brain, Quorum).
- Настраивать резервное копирование, масштабировать узлы чтения (Scale Out) и настраивать пулы подключений (PgBouncer).

---

## Проверка модуля

Чтобы убедиться, что всё выполнено верно, запустите скрипт проверки:

```bash
verify/verify.sh
```

## Уборка

Очистите ресурсы после завершения, чтобы не тратить мощности кластера. Используйте подготовленный скрипт:

```bash
verify/cleanup.sh
```

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами.

1. **Триггер бэкапа**: Изучите манифест CRD `Backup`. Создайте манифест, чтобы запустить резервное копирование прямо сейчас, и дождитесь статуса `Completed`.
2. **Scale Down**: Измените количество инстансов в кластере `my-db` обратно с 3 на 2. Убедитесь, что реплика корректно удалена.
3. **Failover**: Самостоятельно убейте Primary-под и измерьте секундомером, за сколько секунд трафик снова начнет ходить через `rw` сервис.

---

## Шпаргалка

```bash
# === Оператор CloudNativePG ===
kubectl get pods -n cnpg-system                 # Статус оператора

# === Кластер PostgreSQL ===
kubectl -n lab get cluster                      # Общий статус кластеров
kubectl -n lab get pods -l cnpg.io/cluster=my-db  # Поды конкретного кластера
kubectl -n lab get svc -l cnpg.io/cluster=my-db   # Сервисы маршрутизации (rw, ro, r)

# === Секреты и Доступ ===
kubectl -n lab get secret my-db-app -o jsonpath="{.data.password}" | base64 -d
kubectl -n lab exec -it my-db-1 -- psql -U app_user -d app_db

# === Бэкапы ===
kubectl -n lab get scheduledbackup              # Статус бэкапов по расписанию
kubectl -n lab get backup                       # Разовые бэкапы

# === Масштабирование ===
kubectl -n lab patch cluster my-db --type='merge' -p '{"spec":{"instances":3}}'
```


## Решения (Solutions)
В данном модуле добавлены подробные решения для сломанных сценариев в папке `solutions/`. Пожалуйста, изучите их для лучшего понимания.
