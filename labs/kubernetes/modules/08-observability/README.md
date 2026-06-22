# Лабораторная работа 08: Наблюдаемость (events, conditions, logs, metrics)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Часть 1: Events и Conditions](#часть-1-events-и-conditions)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-1)
  - [1.1 Events и Conditions](#11-events-и-conditions)
  - [1.2 Жизненный цикл Events и их компакция](#12-жизненный-цикл-events-и-их-компакция)
- [Часть 2: Логи](#часть-2-логи)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-2)
  - [2.1 Структурированные логи](#21-структурированные-логи)
  - [2.2 Логи упавшего контейнера (--previous)](#22-логи-упавшего-контейнера---previous)
  - [2.3 Многоконтейнерные поды и потоковый вывод](#23-многоконтейнерные-поды-и-потоковый-вывод)
- [Часть 3: Метрики (metrics-server, kubectl top)](#часть-3-метрики-metrics-server-kubectl-top)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-3)
  - [3.1 kubectl top и анализ нагрузки](#31-kubectl-top-и-анализ-нагрузки)
  - [3.2 Usage vs Requests vs Limits](#32-usage-vs-requests-vs-limits)
- [Часть 4: Troubleshooting и runbook](#часть-4-troubleshooting-и-runbook)
  - [Теория: каталог состояний пода + механика back-off](#теория-каталог-состояний-пода--механика-back-off)
  - [Инцидент 1: CrashLoopBackOff](#инцидент-1-crashloopbackoff)
  - [Инцидент 2: OOMKilled (выход за пределы памяти)](#инцидент-2-oomkilled)
  - [Инцидент 3: ImagePullBackOff (ошибка образа)](#инцидент-3-imagepullbackoff)
  - [Бонус: линейный runbook деградации](#бонус-линейный-runbook-деградации)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
  - [Блок 1: События и состояния](#блок-1-события-и-состояния)
  - [Блок 2: Логирование](#блок-2-логирование)
  - [Блок 3: Метрики](#блок-3-метрики)
  - [Блок 4: Troubleshooting](#блок-4-troubleshooting)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
<!-- /TOC -->

> ⏱ время ~35 мин · сложность 2/5 · пререквизиты: Трек 1 (Core), модуль 05 (Storage)

Цель всей работы: диагностировать деградации только средствами кластера — по событиям, условиям, логам и базовым метрикам, без внешнего стека (Loki/Prometheus). К концу модуля вы научитесь собирать линейный runbook инцидента, отличать проблему приложения от проблемы кластера и быстро находить root cause (первопричину) падений подов.

> Все манифесты этой работы лежат в `manifests/`, поломки — в `broken/`,
> эталонные решения — в `solutions/`, автопроверка — в `verify/verify.sh`.
> README — это полный сценарий прохождения; манифесты применяются как файлы.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf

# 1) Рабочий кластер и kubectl, который в него смотрит
kubectl version
kubectl cluster-info

# 2) Namespace для всех ресурсов лабы
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# 3) Очистка окружения от предыдущих запусков
kubectl -n lab delete deploy,sts,ds,job,cronjob,svc,pvc,pod,ingress,netpol,cm,secret --all --ignore-not-found 2>/dev/null

# Удобный алиас на время работы
alias k='kubectl -n lab'
```

---

## Стартовая проверка

Вам потребуется `metrics-server` для Части 3. Проверим его наличие:

```bash
# metrics-server нужен для `kubectl top` и HPA. На managed k8s (GKE, EKS) он есть по умолчанию;
# на kind/minikube/kubeadm — часто ставится отдельно.
kubectl top nodes 2>/dev/null && echo "metrics-server: OK" || echo "metrics-server НЕ установлен — Часть 3 не отработает корректно. Пожалуйста, установите metrics-server."

# Проверка узлов кластера:
kubectl get nodes -o wide
```

Если `metrics-server` отсутствует, его можно установить стандартным манифестом (для локальных стендов может потребоваться флаг `--kubelet-insecure-tls`):
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## Часть 1: Events и Conditions

### Теория для изучения перед частью 1

- **Events (События)** — хронология того, что делал кластер (scheduler, kubelet, controllers) с объектом. Примеры: `Scheduled`, `Pulled`, `Started`, `FailedScheduling`, `BackOff`. События не бесконечны — они живут по умолчанию ~1 час (`--event-ttl` на apiserver), после чего исчезают навсегда.
- **Conditions (Условия/Состояния)** — агрегированное текущее состояние ресурса (`Ready`, `Available`, `Progressing`). Условие обычно содержит поля `status` (True/False/Unknown), `reason` (краткая причина) и `message` (человекочитаемое описание). Это «итог», а events — «история».

**Компакция events (схлопывание).** Повторяющиеся события (одинаковые `involvedObject` + `reason` + `message`) НЕ плодятся по одному в etcd — apiserver их схлопывает. Растёт поле `count`, а поля `firstTimestamp` и `lastTimestamp` держат диапазон. Поэтому в `describe pod` мы часто видим `Warning BackOff 5m (x12 over 8m)` — это одна запись в БД, а не 12 разных строк. Это сделано для защиты etcd от переполнения спамом от падающих подов.

**Каталог conditions по типам ресурсов** (что смотреть на чём):

| Ресурс | Ключевые conditions | Смысл |
|--------|---------------------|-------|
| **Pod** | `PodScheduled` → `Initialized` → `ContainersReady` → `Ready` | Порядок «созревания» пода. Если PodReady=False, трафик к нему не пойдёт. |
| **Deployment** | `Available`, `Progressing` | `Available=True` (есть min реплик), `Progressing=True` (идёт rollout/обновление). |
| **Node** | `Ready`, `MemoryPressure`, `DiskPressure`, `PIDPressure` | Указывает, здорова ли нода и есть ли нехватка критических ресурсов. |
| **PVC/PV** | не conditions, а `phase` | `Pending` (ждёт) / `Bound` (привязан) / `Released` (ожидает очистки). |

---

**Цель:** собрать таймлайн и текущее состояние demo-нагрузки, отличить Event от Condition.
**Ресурс:** `manifests/demo/deploy.yaml` (простое приложение `obs-demo`, пишущее структурированный лог).

---

### 1.1 Events и Conditions

Развернём демонстрационное приложение и посмотрим, как оно проходит свой жизненный цикл:

```bash
kubectl -n lab apply -f manifests/demo/deploy.yaml
kubectl -n lab rollout status deploy/obs-demo --timeout=120s

# Conditions Deployment — агрегированное состояние
kubectl -n lab get deploy obs-demo -o jsonpath='{range .status.conditions[*]}{.type}={.status} ({.reason}){"\n"}{end}'
```

Ожидаемый вывод:
```
Available=True (MinimumReplicasAvailable)
Progressing=True (NewReplicaSetAvailable)
```

Теперь посмотрим на поды. Извлечём Events для конкретного пода из его описания:

```bash
# Получим имя пода
POD_NAME=$(kubectl -n lab get pod -l app=obs-demo -o jsonpath='{.items[0].metadata.name}')

# Прочитаем только секцию Events (в самом конце describe)
kubectl -n lab describe pod $POD_NAME | sed -n '/Events:/,$p'
```

Пример вывода:
```
Events:
  Type    Reason     Age    From               Message
  ----    ------     ----   ----               -------
  Normal  Scheduled  2m15s  default-scheduler  Successfully assigned lab/obs-demo-... to k8s-node-1
  Normal  Pulling    2m14s  kubelet            Pulling image "busybox:1.36"
  Normal  Pulled     2m12s  kubelet            Successfully pulled image "busybox:1.36" in 1.8s
  Normal  Created    2m12s  kubelet            Created container demo
  Normal  Started    2m11s  kubelet            Started container demo
```
Мы видим чёткий таймлайн: Планировщик назначил ноду -> kubelet скачал образ -> kubelet создал и запустил контейнер.

### 1.2 Жизненный цикл Events и их компакция

События можно получать не только через `describe`, но и как самостоятельные объекты.
Это особенно полезно для поиска проблем по всему неймспейсу:

```bash
# Получить все warning-события в неймспейсе, отсортированные по времени
kubectl -n lab get events --field-selector type=Warning --sort-by='.lastTimestamp'

# Получить все события и посмотреть на компакцию (поля COUNT)
kubectl -n lab get events --sort-by='.lastTimestamp' -o custom-columns=LAST_SEEN:.lastTimestamp,COUNT:.count,OBJ:.involvedObject.name,REASON:.reason,MSG:.message | tail -n 10
```

> **Совет:** `kubectl get events --sort-by=.lastTimestamp` — это первая команда, которую стоит выполнить, если "что-то в кластере идёт не так". Она покажет всю ленту происшествий.

---

## Часть 2: Логи

### Теория для изучения перед частью 2

- `kubectl logs` читает stdout и stderr процесса внутри контейнера (именно поэтому в Docker/k8s приложения не должны писать в файлы, а должны писать в консоль).
- Полезные флаги:
  - `--previous` (или `-p`): логи предыдущего упавшего запуска контейнера.
  - `-c <container>`: выбор нужного контейнера в многоконтейнерном поде.
  - `--since=10m` / `--tail=50`: фильтрация по времени и строкам.
  - `-f`: follow (потоковый вывод в реальном времени).
  - `-l <selector>`: чтение логов со всех подов по селектору.
- **Структурированные логи** (`key=value` или JSON) машинно-разбираемы. Вместо "User admin logged in" пишется `{"event":"login", "user":"admin", "level":"info"}`. Это радикально упрощает агрегацию и фильтрацию.

**Откуда `kubectl logs` берёт данные (путь лога):**

```
Контейнер (PID 1)
   │  пишет stdout/stderr
   ▼
CRI (containerd/CRIO)
   │  сохраняет в файл на НОДЕ: /var/log/pods/<namespace>_<pod-name>_<pod-uid>/<container-name>/N.log
   │  (размер лога ограничен политикой kubelet, часто это ~10Mi и ротация 5 файлов)
   ▼
kubectl logs ──> kube-apiserver ──> kubelet (на целевой ноде) ──> читает этот .log файл с диска
```

- **Ограничения `kubectl logs`.**
  1. Логи живут С ПОДОМ. Если вы сделали `kubectl delete pod` или нода упала — логов больше нет (нет центрального хранилища).
  2. Хранится только последняя ротация. Если приложение спамит логами, старые затрутся очень быстро.
  3. Нет поиска и агрегации по многим подам и времени из коробки. Для этого нужен лог-стек (Loki, EFK/ELK, Datadog), который собирает логи с нод в независимую БД.

---

**Цель:** научиться читать логи, фильтровать их и использовать `--previous` для упавших контейнеров.

---

### 2.1 Структурированные логи

Наше демо-приложение пишет логи в формате `key=value`.

```bash
kubectl -n lab logs deploy/obs-demo --tail=5
```
Вывод:
```
ts=2026-06-22T23:05:10+00:00 level=info msg=heartbeat active_connections=42
ts=2026-06-22T23:05:15+00:00 level=info msg=heartbeat active_connections=43
```

Структурированные логи легко фильтровать стандартными unix-утилитами:

```bash
# Фильтрация по уровню 'error' или 'info'
kubectl -n lab logs deploy/obs-demo --tail=50 | grep 'level=info'

# Если логи в JSON (в демо-приложении они k=v, но представим JSON), можно было бы использовать `jq`.
```

### 2.2 Логи упавшего контейнера (--previous)

Это критически важный инструмент. Когда контейнер падает (например, по `CrashLoopBackOff`), kubelet его немедленно перезапускает. Обычный `kubectl logs` покажет логи **НОВОГО** (уже перезапущенного) контейнера, который, возможно, ещё не успел упасть или только инициализируется. Причина падения осталась в **СТАРОМ** контейнере.

```bash
# Читаем логи предыдущего завершённого контейнера:
# kubectl -n lab logs <pod_name> --previous
# (Мы отработаем это на практике в Части 4 с инцидентом CrashLoopBackOff)
```

**Нюанс:** `--previous` не сработает, если предыдущего запуска не было или если лог уже был ротирован. Если контейнер падает за доли секунды (например, опечатка в команде), лог может даже не успеть записаться. В таком случае причину берут из `lastState.terminated` (см. Часть 4).

### 2.3 Многоконтейнерные поды и потоковый вывод

Если в поде несколько контейнеров (например, приложение + envoy sidecar proxy), `kubectl logs` потребует указать имя контейнера:

```bash
# Ошибка: a container name must be specified for pod ...
# kubectl -n lab logs <pod_name>

# Правильно:
# kubectl -n lab logs <pod_name> -c <container_name>
```

---

## Часть 3: Метрики (metrics-server, kubectl top)

### Теория для изучения перед частью 3

- **metrics-server** собирает базовые метрики (CPU и RAM) подов и нод. Он отдаёт их утилите `kubectl top` и контроллеру HPA (Horizontal Pod Autoscaler). Это метрики «здесь и сейчас», у metrics-server **НЕТ ИСТОРИИ**.
- Для истории, алертов и красивых дашбордов нужен **Prometheus + Grafana**. `metrics-server` их не заменяет!

**Пайплайн метрик (откуда берётся `kubectl top`):**

```
kubelet / cAdvisor на КАЖДОЙ ноде (анализирует cgroups контейнеров через /metrics/resource)
        │  scrape каждые ~15 секунд
        ▼
metrics-server (агрегирует данные со всех нод, держит В ПАМЯТИ только последние точки)
        │  регистрирует Metrics API в kube-apiserver
        ▼
metrics.k8s.io  ──>  вызов `kubectl top` или цикл `HPA`
```

**metrics-server vs Prometheus** (часто путают — это РАЗНЫЕ инструменты):

| Характеристика | metrics-server | Prometheus |
|---|---|---|
| **Что отдаёт** | CPU/RAM (только базовые ресурсы) | Любые метрики (app, kube-state, node-exporter) |
| **Хранение** | В оперативной памяти, только текущий срез | База данных временных рядов (TSDB) на диске (история за дни/месяцы) |
| **Язык запросов**| Нет, просто готовые значения | PromQL (мощный язык аналитики) |
| **Потребители** | `kubectl top`, HPA | Grafana (дашборды), Alertmanager (алерты), HPA (через Prometheus Adapter) |

---

### 3.1 kubectl top и анализ нагрузки

Посмотрим на текущее потребление:

```bash
# Потребление ресурсов нодами
kubectl top nodes
# Пример вывода:
# NAME        CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# k8s-node-1  120m         6%     780Mi           27%

# Потребление ресурсов подами в нашем namespace
kubectl top pods -n lab
# Пример вывода:
# NAME                     CPU(cores)   MEMORY(bytes)
# obs-demo-7f8b9...        1m           2Mi
```

> **Важно:** Сразу после старта пода возможна ошибка `metrics not available yet`. `metrics-server` собирает данные с задержкой в 1-2 минуты окнами агрегации. Просто подождите. Ошибка `Metrics API not available` (без "yet") означает, что сам `metrics-server` не установлен.

### 3.2 Usage vs Requests vs Limits

Самая частая путаница при сайзинге и траблшутинге: три разных числа из трёх разных источников. **Их нельзя смешивать.**

| Понятие | Что это такое | Откуда взять | На что влияет |
|---|---|---|---|
| **Usage** (Факт) | Сколько контейнер ПОТРЕБЛЯЕТ прямо сейчас. Меняется ежесекундно. | `kubectl top pod` (данные от metrics-server). | Ничего не гарантирует. Используется HPA для скейлинга. |
| **Requests** (Резерв) | Сколько планировщик РЕЗЕРВИРУЕТ под Pod. | `kubectl describe node` (Allocated resources) или `describe pod` (Requests). | **Планирование**. Pod встанет на ноду, только если на ней хватает свободных *requests*, независимо от текущего *usage*. |
| **Limits** (Потолок) | Жёсткий предел. CPU троттлится, RAM ⇒ OOMKilled. | `kubectl describe pod` (Limits) или манифест пода. | **Enforcement** (ограничение) ядром Linux через cgroups. |

```text
Визуализация:

   0 ──── requests ──────── usage(сейчас) ──── limits ─────► ресурс (CPU/RAM)
   │      (резерв,           (факт,            (потолок,
   │       для scheduler)     для top)          для cgroup)

usage может быть НИЖЕ requests (зря зарезервировано, нода "простаивает") или
ВЫШЕ requests (burst в пределах limits) — это нормально и зависит от профиля нагрузки.
```

**Реальность:**
```bash
# 1) USAGE — реальное потребление
kubectl top node k8s-node-1

# 2) REQUESTS/LIMITS — сумма по всем подам ноды (резерв и потолки)
kubectl describe node k8s-node-1 | grep -A 5 "Allocated resources:"
```
Вы можете увидеть, что нода загружена на 10% CPU по `top` (Usage), но зарезервирована на 95% по `Allocated resources` (Requests). Планировщик больше подов на неё не пустит, хотя физически она почти свободна. Это классическая проблема "перерезервирования" (over-provisioning).

---

## Часть 4: Troubleshooting и runbook

### Теория: каталог состояний пода + механика back-off

Большинство инцидентов сводятся к одному из типовых состояний. Распознал состояние → знаешь первую команду для поиска причины.

| Состояние пода | Что значит | Первая команда / Где искать причину |
|----------------|------------|-------------------------------------|
| `Pending` | Не может быть запланирован на ноду. | `describe pod` → Events: `FailedScheduling` (Insufficient cpu, несовпадение taint/toleration, не готов PVC). |
| `ContainerCreating` | Завис при запуске (образ/том/секрет не готовы). | `describe pod` → Events (timeout mount, secret not found). |
| `ImagePullBackOff` | Образ не качается. | `describe pod` → Events (опечатка в теге, нет прав/registry недоступен). |
| `CrashLoopBackOff` | Контейнер падает (exit != 0) и рестартует. | `logs --previous` или `describe pod` → `lastState.terminated`. |
| `OOMKilled` (в lastState) | Превышен лимит памяти (`limits.memory`). | `describe pod` → `lastState.reason=OOMKilled` (нужно поднять limit или чинить утечку памяти). |
| `Evicted` | Вытеснен kubelet-ом из-за давления на ноде. | `describe node` → `DiskPressure` или `MemoryPressure`. |
| `Terminating` | Завис при удалении. | `describe pod` → проблема с `finalizers` или долгий `terminationGracePeriodSeconds`. |

**Механика Back-Off:**
Если контейнер падает (CrashLoop), kubelet не рестартует его каждую миллисекунду (иначе он бы сжёг весь CPU ноды). Применяется **экспоненциальная задержка (back-off)**: `10s → 20s → 40s → 80s → 160s → 300s`.
Потолок — **300 секунд (5 минут)**. Если вы видите `CrashLoopBackOff`, не удивляйтесь, что поды не поднимаются моментально после исправления бага, они могут ждать свой 5-минутный таймер. Счётчик сбрасывается, если контейнер проработал стабильно ~10 минут.

**OOMKilled vs Evicted** (частая путаница):
- **OOMKilled**: Ядро Linux убило ОДИН конкретный контейнер за превышение его собственного `limits.memory` (exit code 137). Под остаётся на ноде, контейнер рестартует.
- **Evicted**: kubelet выселил ВЕСЬ под целиком, потому что на самой НОДЕ кончилась физическая память или место на диске. Под удаляется с ноды и (если это ReplicaSet) планируется на другую.

---

### Инцидент 1: CrashLoopBackOff

Приложение постоянно падает сразу после старта.

**Воспроизведение:**
```bash
# Команда контейнера намеренно завершается с exit 1
kubectl -n lab apply -f broken/scenario-01-crashloop/deploy.yaml 2>/dev/null || \
cat <<EOF | kubectl -n lab apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: obs-broken
spec:
  replicas: 1
  selector: { matchLabels: { app: obs-broken } }
  template:
    metadata: { labels: { app: obs-broken } }
    spec:
      containers:
      - name: broken-app
        image: busybox:1.36
        command: ["sh", "-c", "echo 'Starting up...'; sleep 2; echo 'CRITICAL ERROR: DB connection failed'; exit 1"]
EOF

sleep 15
```

**Диагностика:**
```bash
# Видим растущие рестарты и CrashLoopBackOff
kubectl -n lab get pod -l app=obs-broken
# obs-broken-...   0/1   CrashLoopBackOff   3 (20s ago)   45s

# 1. Проверяем логи предыдущего упавшего запуска (--previous)
kubectl -n lab logs -l app=obs-broken --previous --tail=10
# Вывод покажет: "CRITICAL ERROR: DB connection failed"

# 2. Проверяем код завершения в lastState
POD_BROKEN=$(kubectl -n lab get pod -l app=obs-broken -o name)
kubectl -n lab get $POD_BROKEN -o jsonpath='{"Reason: "}{.status.containerStatuses[0].lastState.terminated.reason}{"\nExit Code: "}{.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
# Вывод:
# Reason: Error
# Exit Code: 1
```
*Решение:* Исправить конфиг подключения к БД (в реальности).
*Профилактика:* Настроить алерты в Prometheus на метрику `kube_pod_container_status_restarts_total > 0`.

---

### Инцидент 2: OOMKilled (выход за пределы памяти)

Контейнер пытается аллоцировать больше памяти, чем ему разрешено лимитами.

**Воспроизведение:**
```bash
cat <<EOF | kubectl -n lab apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: oom-demo
spec:
  containers:
  - name: memory-hog
    image: polinux/stress
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "150M", "--vm-hang", "1"]
    resources:
      limits:
        memory: "100Mi"
EOF

sleep 10
```

**Диагностика:**
```bash
kubectl -n lab get pod oom-demo
# Видим состояние OOMKilled или CrashLoopBackOff (но первопричина другая)

# Смотрим детально причину завершения:
kubectl -n lab get pod oom-demo -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
# OOMKilled

# Смотрим events:
kubectl -n lab describe pod oom-demo | grep -i oom
```
*Решение:* Увеличить `limits.memory` до 200Mi или (что правильнее) оптимизировать приложение (уменьшить хип JVM, размер пула и т.д.).

---

### Инцидент 3: ImagePullBackOff (ошибка образа)

Опечатка в имени образа или отсутствие доступа к registry.

**Воспроизведение:**
```bash
cat <<EOF | kubectl -n lab apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: image-err-demo
spec:
  containers:
  - name: app
    image: nginx:1.999.999-typo
EOF

sleep 5
```

**Диагностика:**
```bash
kubectl -n lab get pod image-err-demo
# image-err-demo   0/1   ImagePullBackOff   0   10s

# В логах будет ПУСТО! Потому что контейнер даже не был создан.
# kubectl -n lab logs image-err-demo -> Error from server (BadRequest)

# Смотрим events!
kubectl -n lab describe pod image-err-demo | sed -n '/Events:/,$p'
# Вывод:
# Warning  Failed     ...  Failed to pull image "nginx:1.999.999-typo": rpc error: code = NotFound desc = failed to pull and unpack image...
```
*Решение:* Исправить тег образа на существующий (`nginx:latest`).

---

### Бонус: линейный runbook деградации

Когда вы приходите на сломанный кластер, следуйте чёткому линейному пайплайну:

1. **Что не так и с каких пор? (Верхний уровень)**
   ```bash
   kubectl -n lab get pods -o wide
   kubectl -n lab get events --sort-by=.lastTimestamp | tail -15
   ```
2. **Почему так вышло? (Уровень контроллера и пода)**
   ```bash
   kubectl -n lab describe pod <имя_проблемного_пода>
   # Внимательно читаем Conditions и Events внизу.
   ```
3. **Что говорит само приложение? (Уровень процесса)**
   ```bash
   kubectl -n lab logs <имя_пода> [--previous]
   ```
4. **Хватает ли ресурсов? (Уровень ноды)**
   ```bash
   kubectl top nodes
   kubectl top pods -n lab
   kubectl describe node <имя_ноды> | grep -A 5 "Allocated resources"
   ```
5. **Сеть доходит? (Если приложение Running, но недоступно)**
   ```bash
   kubectl -n lab get svc,endpoints,ingress
   ```

Линейность важна: нет смысла читать логи (`шаг 3`), если под в статусе `Pending` и даже не получил ноду (`шаг 2`), и нет смысла дебажить сеть (`шаг 5`), если приложение находится в `CrashLoopBackOff` (`шаг 1`).

---

## Проверка модуля

Проверим, что мы успешно усвоили материал.

```bash
# Убедимся, что obs-demo работает и пишет логи
kubectl -n lab get deploy obs-demo
kubectl -n lab logs deploy/obs-demo --tail=2

# Скрипт проверки (если доступен на стенде):
# bash verify/verify.sh
```

---

## Финальная карта ресурсов модуля

| Ресурс / Сущность | Что демонстрирует |
|-------------------|-------------------|
| `obs-demo` | Структурированные логи, `Events`/`Conditions`, базовые метрики `top`. |
| `obs-broken` | `CrashLoopBackOff`, поиск ошибки через `logs --previous` и `lastState`. |
| `oom-demo` | Превышение памяти, `OOMKilled` (exit 137). |
| `image-err-demo` | `ImagePullBackOff`, диагностика проблем до запуска контейнера через Events. |

---

## Теоретические вопросы (итоговые)

### Блок 1: События и состояния
1. Чем `Events` отличаются от `Conditions`?
2. Почему events нельзя считать долговременным архивом логов аудита?
3. Что означает `Available=True` у Deployment?
4. Зачем apiserver "схлопывает" повторяющиеся события (`count`, `lastTimestamp`)?

### Блок 2: Логирование
5. В каких случаях обычный `kubectl logs` бесполезен и необходимо использовать флаг `--previous`?
6. Почему структурированные логи (JSON) упрощают расследование инцидентов в продакшене?
7. Как прочитать логи конкретного контейнера в многоконтейнерном поде? Опишите команду.

### Блок 3: Метрики
8. Какая разница между метриками `Usage`, `Requests` и `Limits`? Откуда берется каждое из этих значений?
9. Что даёт кластеру компонент `metrics-server` и чего он принципиально НЕ умеет по сравнению с Prometheus?
10. Почему `kubectl top nodes` может показывать загрузку CPU 15%, но при этом поды остаются в `Pending` из-за нехватки CPU (Insufficient cpu)?

### Блок 4: Troubleshooting
11. Что такое `CrashLoopBackOff` и как работает алгоритм экспоненциальной задержки рестартов?
12. В чём фундаментальная разница между `OOMKilled` и `Evicted`? Кого убивает ядро, а кого выселяет kubelet?
13. Опишите правильный порядок шагов диагностики (runbook) при падающем приложении.

---

## Практические задания (отработка)

> Выполняйте эти задания на живом кластере, не подглядывая в шпаргалку.

1. **Диагностика:** Выведите все события в namespace `kube-system`, отсортированные по времени последнего появления. Найдите самое свежее `Warning` событие, если оно есть.
2. **Логирование:** Найдите под CoreDNS в namespace `kube-system`. Выведите его последние 20 строк логов.
3. **Метрики:** Выведите `kubectl top nodes`. Затем сравните вывод с `Allocated resources` через `kubectl describe node`. Найдите разницу между потребляемыми ресурсами и зарезервированными.
4. **JSONPath:** Выведите статус `Conditions` пода `obs-demo` с помощью форматирования jsonpath: `-o jsonpath='{.status.conditions}'`. Сравните с обычным `describe`.
5. **CrashLoop:** Создайте под, который запускает команду `ls /non-existent-dir`. Дождитесь статуса `CrashLoopBackOff` и найдите код ошибки `exitCode` одной командой с помощью JSONPath или `describe`.

---

## Шпаргалка

```bash
# === Events и Conditions ===
kubectl -n lab get events --sort-by=.lastTimestamp | tail -20
kubectl -n lab get events --field-selector type=Warning
kubectl -n lab describe pod <имя_пода> | sed -n '/Events:/,$p'
kubectl -n lab get deploy <имя_deploy> -o jsonpath='{.status.conditions}'

# === Логи ===
kubectl -n lab logs deploy/<имя_deploy> --tail=50 -f
kubectl -n lab logs <имя_пода> --previous            # логи упавшего (предыдущего) запуска
kubectl -n lab logs <имя_пода> -c <имя_контейнера>   # логи нужного контейнера
kubectl -n lab logs -l app=my-app                    # логи по селектору меток

# === Метрики и Ресурсы ===
kubectl top nodes
kubectl top pods -n lab
kubectl describe node <имя_ноды> | grep -A 5 "Allocated resources"

# === Причина рестарта и статус ===
# Получить причину завершения предыдущего контейнера:
kubectl -n lab get pod <имя_пода> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'

# === Быстрый runbook пода ===
kubectl get pod <имя> -o yaml | grep -A 5 "lastState:"
```

---

## Чему вы научились

В этом модуле вы научились:
- Работать с событиями (Events) Kubernetes для понимания истории происходящего с объектами кластера.
- Анализировать состояния (Conditions) ресурсов.
- Чтению, фильтрации и анализу логов контейнеров, включая использование `--previous` для поиска root cause упавших приложений.
- Пониманию разницы между метриками Usage, Requests и Limits.
- Пользоваться утилитой `kubectl top` и понимать ограничения `metrics-server`.
- Применять пошаговый линейный runbook для диагностики инцидентов (`Pending`, `CrashLoopBackOff`, `OOMKilled`, `ImagePullBackOff`).

## Уборка

Очистите ресурсы после выполнения лабораторной работы:

```bash
kubectl -n lab delete deploy obs-demo obs-broken --ignore-not-found
kubectl -n lab delete pod oom-demo image-err-demo --ignore-not-found
kubectl delete ns lab
```
�итичным сервисам (модуль 02 — QoS, модуль 12).
- **Кооперация с scheduler:** при `MemoryPressure` на ноду перестают планировать
  новые поды (taint `node.kubernetes.io/memory-pressure`). Выселенный под
  пересоздаётся контроллером — и может сесть на другую ноду.
- Признак: `kubectl get pod` → `Evicted`; причина в `describe node` (Conditions
  `MemoryPressure/DiskPressure=True`) и в events ноды.

---

### Инцидент 1: `CrashLoopBackOff`

Оформлен в `broken/scenario-01/`. Здесь — полный цикл.

**Воспроизведение:**

```bash
# Команда контейнера завершается с exit 1 сразу после старта
kubectl -n lab apply -f broken/scenario-01/deploy.yaml
sleep 15
```

**Диагностика:**

```bash
kubectl -n lab get pod -l app=obs-broken
# obs-broken-...   0/1   CrashLoopBackOff   3 (20s ago)   45s
#                  ^ растущий back-off между рестартами

# Логи последнего УПАВШЕГО запуска. ВАЖНО: для очень короткого контейнера
# (echo+exit за <1с) логи могут не успеть сохраниться — тогда будет
# 'unable to retrieve container logs', и причину надёжнее брать из lastState ниже.
kubectl -n lab logs -l app=obs-broken --previous --tail=2
# fail        (либо 'unable to retrieve...' если контейнер жил доли секунды)

# Код и причина завершения
kubectl -n lab get pod -l app=obs-broken \
  -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}{" exit="}{.items[0].status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
# Error exit=1
```

**Решение:**

```bash
kubectl -n lab apply -f solutions/01-crashloop/deploy.yaml
kubectl -n lab rollout status deploy/obs-broken --timeout=120s
```

**Профилактика:** PID 1 контейнера должен быть долгоживущим процессом; алёрт на
`RESTARTS > 0` и на `reason=CrashLoopBackOff`.

### Бонус: линейный runbook деградации

```bash
# 1) Что не так и с каких пор
kubectl -n lab get pods -o wide
kubectl -n lab get events --sort-by=.lastTimestamp | tail -15
# 2) Почему (состояние и причина)
kubectl -n lab describe pod <pod>
# 3) Что говорит приложение
kubectl -n lab logs <pod> [--previous]
# 4) Ресурсы (давление?)
kubectl top nodes && kubectl top pods -n lab
# 5) Сеть (если сервис)
kubectl -n lab get svc,endpoints,ingress
```

**Контрольные вопросы:**
1. Что такое `CrashLoopBackOff` и как растёт интервал рестартов?
2. Почему при CrashLoop нужен `--previous`?
3. Опишите порядок шагов runbook и зачем он линеен.

---

## Проверка модуля

```bash
kubectl -n lab apply -f manifests/demo/deploy.yaml
kubectl -n lab rollout status deploy/obs-demo --timeout=120s

bash verify/verify.sh
# [OK] obs-demo logs are structured (contain 'level=')
# [OK] module 08 verified
```

`verify.sh` проверяет: namespace `lab` → `Deployment/obs-demo` готов → у пода
есть логи → логи структурированы (содержат `level=`). Две `[OK]`-строки от
`ok`-вызовов; промежуточные проверки молчат.

---

## Финальная карта ресурсов модуля

| Ресурс | Что демонстрирует |
|--------|-------------------|
| `obs-demo` | структурированные логи, events/conditions, метрики |
| `obs-broken` | CrashLoopBackOff, `logs --previous`, lastState |

---

## Теоретические вопросы (итоговые)

1. Сопоставьте сигналы: events / conditions / logs / metrics — что даёт каждый?
2. Почему для диагностики нужны все четыре, а не один? Как apiserver схлопывает
   повторяющиеся events (`count`/`lastTimestamp`)?
3. Опишите путь лога от stdout до `kubectl logs`. Зачем `--previous` и три
   ограничения `kubectl logs` (почему нужен Loki/ELK)?
4. Чем `metrics-server` ограничен против Prometheus? Назовите три уровня Metrics
   API и кто их реализует.
5. Как растёт интервал back-off у CrashLoopBackOff (и где потолок)? Чем OOMKilled
   отличается от Evicted?
6. Как отличить проблему приложения от проблемы ноды/кластера? Зачем нужен runbook?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Спровоцируйте `CrashLoopBackOff` и достаньте причину из `logs --previous` и `lastState.terminated`.
2. Соберите «ленту проблем»: `get events --sort-by=.lastTimestamp` + найдите компакцию (`x.. over ..`).
3. Сравните `kubectl top pods` с `describe node` (Allocated) — объясните разницу «usage vs requests».
4. Выведите `conditions` пода и Deployment через jsonpath; сопоставьте с порядком созревания пода.
5. Найдите OOMKilled-под по `lastState.reason` одной командой по всему namespace.

---

## Шпаргалка

```bash
# === Events / Conditions ===
kubectl -n lab get events --sort-by=.lastTimestamp | tail -20
kubectl -n lab describe pod <p> | sed -n '/Events:/,$p'
kubectl -n lab get deploy <d> -o jsonpath='{.status.conditions}'

# === Логи ===
kubectl -n lab logs deploy/<d> --tail=50 -f
kubectl -n lab logs <pod> --previous            # упавший запуск
kubectl -n lab logs <pod> -c <container>        # нужный контейнер

# === Метрики ===
kubectl top nodes
kubectl top pods -n lab

# === Причина рестарта ===
kubectl -n lab get pod <p> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'

# === Уборка ===
kubectl -n lab delete -k manifests/ ; kubectl -n lab delete deploy obs-broken --ignore-not-found
```

---


## Чему вы научились

В этом модуле вы научились:
- Чтению и анализу логов контейнеров
- Работе с Events Kubernetes для диагностики проблем
- Пониманию концепций метрик и трейсинга

## Уборка

```bash
kubectl -n lab delete -k manifests/
kubectl -n lab delete deploy obs-broken --ignore-not-found
```
