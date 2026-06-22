# Лабораторная работа 12: Управление ресурсами (QoS, PriorityClass, preemption, limits)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Часть 1: requests/limits и механизмы планирования](#часть-1-requestslimits-и-механизмы-планирования)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-1)
  - [1.1 Поведение при нехватке CPU (сжимаемый ресурс)](#11-поведение-при-нехватке-cpu)
  - [1.2 Поведение при нехватке Памяти (несжимаемый ресурс)](#12-поведение-при-нехватке-памяти)
  - [1.3 Overcommit и гарантированное резервирование](#13-overcommit-и-гарантированное-резервирование)
- [Часть 2: QoS-классы (Quality of Service)](#часть-2-qos-классы)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-2)
  - [2.1 Guaranteed: Высший приоритет выживаемости](#21-guaranteed-высший-приоритет-выживаемости)
  - [2.2 Burstable: Баланс ресурсов](#22-burstable-баланс-ресурсов)
  - [2.3 BestEffort: Первые кандидаты на выселение](#23-besteffort-первые-кандидаты-на-выселение)
  - [2.4 Практика: Создание подов разных классов](#24-практика-создание-подов-разных-классов)
  - [2.5 Глубокое погружение: OOM Score Adj в cgroups](#25-глубокое-погружение-oom-score-adj-в-cgroups)
- [Часть 3: PriorityClass и Вытеснение (Preemption)](#часть-3-priorityclass-и-вытеснение-preemption)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-3)
  - [3.1 Как работает PriorityClass](#31-как-работает-priorityclass)
  - [3.2 Подготовка ноды для детерминированного вытеснения](#32-подготовка-ноды-для-детерминированного-вытеснения)
  - [3.3 Заполнение ноды low-prio подами](#33-заполнение-ноды-low-prio-подами)
  - [3.4 Демонстрация: High-prio вытесняет low-prio](#34-демонстрация-high-prio-вытесняет-low-prio)
  - [3.5 Анализ событий вытеснения (Preempted)](#35-анализ-событий-вытеснения-preempted)
- [Часть 4: LimitRange и ResourceQuota: Защита кластера](#часть-4-limitrange-и-resourcequota-защита-кластера)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-4)
  - [4.1 Установка дефолтных лимитов через LimitRange](#41-установка-дефолтных-лимитов-через-limitrange)
  - [4.2 Защита неймспейса через ResourceQuota](#42-защита-неймспейса-через-resourcequota)
- [Часть 5: Enforcement лимитов — CPU throttle vs Memory OOM](#часть-5-enforcement-лимитов--cpu-throttle-vs-memory-oom)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-5)
  - [5.1 CPU Throttle в действии](#51-cpu-throttle-в-действии)
  - [5.2 OOMKilled в действии и методы починки](#52-oomkilled-в-действии-и-методы-починки)
- [Часть 6: Troubleshooting — боевые инциденты](#часть-6-troubleshooting--боевые-инциденты)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-6)
  - [Инцидент 1: Pod навсегда в Pending (Insufficient CPU/Memory)](#инцидент-1-pod-навсегда-в-pending-insufficient-cpumemory)
  - [Инцидент 2: Приложение тормозит, но нода не загружена (CPU Throttling)](#инцидент-2-приложение-тормозит-но-нода-не-загружена-cpu-throttling)
  - [Инцидент 3: OOMKilled (Exit Code 137)](#инцидент-3-oomkilled-exit-code-137)
  - [Инцидент 4: Неожиданное выселение подов (Evicted)](#инцидент-4-неожиданное-выселение-подов-evicted)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
  - [Блок 1: Requests, Limits и cgroups](#блок-1-requests-limits-и-cgroups)
  - [Блок 2: QoS и Eviction](#блок-2-qos-и-eviction)
  - [Блок 3: PriorityClass и Preemption](#блок-3-priorityclass-и-preemption)
  - [Блок 4: Troubleshooting](#блок-4-troubleshooting)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
<!-- /TOC -->

> ⏱ время ~35 мин · сложность 3/5 · пререквизиты: Трек 1 (Core), модуль 02 (введение), модуль 06 (квоты)

---

Цель всей работы: научиться осознанно управлять тем, **сколько** ресурсов получают поды в кластере, и **кто** важнее при их нехватке. Мы изучим, как задавать `requests` и `limits`, как Kubernetes автоматически назначает QoS-классы на их основе, и как работает механизм `PriorityClass` с вытеснением (preemption). Вы увидите разницу между CPU-throttling и Memory-OOMKilled на живых примерах.

К концу модуля вы научитесь назначать приоритеты, читать причины OOMKilled, видеть preemption вживую и избегать типовых проблем производительности, связанных с ресурсами.

> Все манифесты этой работы лежат в `manifests/`, поломки — в `broken/`,
> эталонные решения — в `solutions/`, автопроверка — в `verify/verify.sh`.
> README — это полный сценарий прохождения; манифесты применяются как файлы.

---

## Предварительные требования

Для прохождения лабораторной работы вам потребуется рабочий кластер Kubernetes с доступом администратора. Мы предполагаем использование нашего стандартного стенда на базе Kubespray (или Minikube/Kind).

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf

# Проверяем, что кластер доступен и отвечает
kubectl cluster-info
kubectl version --short 2>/dev/null || kubectl version
```

Для того чтобы ресурсы нашей лаборатории не перемешивались с другими приложениями, мы создадим отдельный неймспейс `lab` и очистим его, если он уже существует:

```bash
# Создание Namespace для всех ресурсов лабы
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# Удобный алиас на время работы (сократит ввод команд)
alias k='kubectl -n lab'

# Очистка предыдущих запусков (если были)
k delete deploy,pod,priorityclass,limitrange,resourcequota --all --ignore-not-found 2>/dev/null
```

---

## Стартовая проверка

Давайте проверим ёмкость наших нод. Это крайне важно для понимания того, как планировщик (kube-scheduler) принимает решения, и для проведения демонстрации вытеснения (preemption) в Части 3.

```bash
# Посмотрим на список всех нод и их статусы
kubectl get nodes

# Извлечем точную ёмкость worker-нод (allocatable)
# Эта метрика показывает, сколько реально доступно для пользовательских подов,
# за вычетом резервов для kubelet и OS.
kubectl get nodes -l '!node-role.kubernetes.io/control-plane' \
  -o custom-columns='NODE:.metadata.name,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory'
```

Ожидаемый вывод:
```text
NODE      CPU     MEM
k8s-w-1   1400m   3118188Ki
k8s-w-2   1400m   3118188Ki
```

> **Важно:** В Kubernetes `1000m` (милликор) равно `1 CPU` (одному ядру). Следовательно, `1400m` — это 1.4 ядра. Единицы измерения памяти указываются в Ki, Mi, Gi. Обратите внимание, что `allocatable` всегда меньше физического объема узла.

---

## Часть 1: requests/limits и механизмы планирования

### Теория для изучения перед частью

- **`requests` (запросы)** — это **ГАРАНТИЯ**. Scheduler использует это значение для поиска ноды, на которой есть ровно столько свободного места (или больше). Если узел имеет `1000m` свободного CPU, а ваш под просит `1100m`, он туда не попадёт.
- **`limits` (лимиты)** — это **ПОТОЛОК**. Это жесткое ограничение, накладываемое через подсистему `cgroups` ядра Linux. Под не сможет потреблять больше ресурсов, чем указано в `limits`.
- В Kubernetes ресурсы делятся на:
  - **Сжимаемые (Compressible):** CPU. Если процесс достигает лимита, он не убивается, а просто замедляется (Throttling).
  - **Несжимаемые (Incompressible):** RAM. Если процесс пытается выделить больше памяти, чем позволяет `limits`, ядро немедленно убивает его с сигналом `OOMKilled` (Out Of Memory Killed).

### 1.1 Поведение при нехватке CPU

CPU-ресурс измеряется во времени выполнения на процессоре. Когда под исчерпывает свой `limits.cpu`, механизм CFS Quota (Completely Fair Scheduler) ставит процесс на паузу до начала следующего окна (обычно 100мс). 

Это проявляется как **Throttling** — процесс продолжает работать, но медленнее, так как часть времени он находится в состоянии заморозки. Приложение может рапортовать о высоких latency или таймаутах, хотя мониторинг ноды показывает недогруженный CPU.

### 1.2 Поведение при нехватке Памяти

Память нельзя "поставить на паузу". Если процессу нужна память для работы, а предел `limits.memory` исчерпан, контроллер памяти cgroups отправляет процессу сигнал `SIGKILL`.

В статусе пода это будет отражено как:
`State: Terminated`
`Reason: OOMKilled`
`Exit Code: 137` (128 + 9 = SIGKILL).

### 1.3 Overcommit и гарантированное резервирование

Kubernetes позволяет настроить **Overcommit** (переподписку). Это означает, что сумма всех `limits` на ноде может значительно превышать её физическую ёмкость. 

Почему это работает?
- Потому что планирование происходит исключительно на основе `requests`!
- Если сумма `requests` всех подов не превышает `allocatable`, нода считается валидной.
- Лимиты (`limits`) могут быть больше, позволяя подам в моменты пиковых нагрузок "забирать" свободные ресурсы у простаивающих соседей.

Если нода переподписана и все поды внезапно начнут утилизировать ресурсы до своих `limits`, возникнет нехватка памяти (Node-pressure). Тогда вмешивается Kubelet и начинает **выселять (Evict)** поды. Кого он выселит первым? На этот вопрос отвечают QoS-классы.

---

## Часть 2: QoS-классы (Quality of Service)

### Теория для изучения перед частью

Kubernetes **автоматически** присваивает каждому поду один из трёх QoS-классов. Вы не можете задать класс вручную (например, написав `qosClass: Guaranteed` в манифесте). Класс вычисляется на основе соотношения `requests` и `limits` во всех контейнерах пода.

Порядок выселения при переполнении памяти на ноде выглядит так (от первых к последним):
`BestEffort` → `Burstable` → `Guaranteed`

### 2.1 Guaranteed: Высший приоритет выживаемости

Класс `Guaranteed` присваивается поду только в том случае, если для **ВСЕХ** его контейнеров выполняется условие:
`requests.cpu == limits.cpu` И `requests.memory == limits.memory`.

Эти поды считаются самыми важными. Они получают гарантированный резерв и выселяются последними (только если на ноде закончилась память, а подов других классов больше нет).

### 2.2 Burstable: Баланс ресурсов

Класс `Burstable` (взрывной, импульсный) присваивается, если:
- Под имеет `requests` и `limits`, но они **не равны** (например, запрошено 100m, а лимит 500m).
- Ресурсы заданы хотя бы для одного контейнера, но не для всех.

Это самый частый класс для обычных микросервисов. Он гарантирует базовый минимум, но позволяет использовать больше ресурсов, если они свободны на ноде. При нехватке памяти такие поды выселяются вторыми.

### 2.3 BestEffort: Первые кандидаты на выселение

Класс `BestEffort` присваивается подам, у которых **вообще не заданы** ни `requests`, ни `limits`.

Такие поды не дают планировщику понимания об их аппетитах, поэтому могут быть запланированы на любую ноду, где есть хоть сколько-то места. Однако при первых признаках нехватки ресурсов Kubelet безжалостно убивает (Evict) эти поды. Идеально подходят для фоновых батч-задач или CI/CD воркеров.

### 2.4 Практика: Создание подов разных классов

Давайте создадим три пода и убедимся, что Kubernetes правильно назначил им QoS-классы. В манифесте `manifests/qos.yaml` определены:
1. `qos-guaranteed` (requests == limits)
2. `qos-burstable` (requests < limits)
3. `qos-besteffort` (без requests/limits)

```yaml
# Фрагмент manifests/qos.yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: qos-guaranteed
  namespace: lab
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    resources:
      requests: { cpu: "100m", memory: "100Mi" }
      limits:   { cpu: "100m", memory: "100Mi" } # requests == limits
```

Применим манифест:

```bash
k apply -f manifests/qos.yaml
```

Проверим назначенные классы через jsonpath:

```bash
for p in qos-guaranteed qos-burstable qos-besteffort; do
  CLASS=$(k get pod $p -o jsonpath='{.status.qosClass}')
  echo "Pod $p -> QoS Class: $CLASS"
done
```

Ожидаемый вывод:
```text
Pod qos-guaranteed -> QoS Class: Guaranteed
Pod qos-burstable -> QoS Class: Burstable
Pod qos-besteffort -> QoS Class: BestEffort
```

> **Вывод:** Kubernetes неукоснительно следует правилу вычисления QoS. Если вам критически важно, чтобы СУБД (например, PostgreSQL) никогда не выселялась с ноды — обеспечьте ей `Guaranteed` класс (установив жесткое равенство requests и limits).

### 2.5 Глубокое погружение: OOM Score Adj в cgroups

Ядро Linux использует параметр `oom_score_adj` (от -1000 до 1000) для принятия решения о том, какой процесс убить при наступлении OOM на системном уровне. Чем выше score, тем вероятнее смерть.

Kubelet настраивает этот параметр в зависимости от QoS:
- `Guaranteed`: `oom_score_adj` = -997
- `BestEffort`: `oom_score_adj` = 1000 (максимально убиваемый)
- `Burstable`: динамическое значение, зависящее от использования (обычно от 2 до 999)

Это гарантирует, что даже если сам Kubelet не успеет провести "вежливое" выселение (Eviction), ядро Linux через OOM-Killer всё равно убьет `BestEffort` процессы первыми, защитив `Guaranteed`.

**Контрольные вопросы (Часть 1 и 2):**
1. В чём разница между `requests` и `limits` с точки зрения Scheduler?
2. Какой компонент следит за `limits` и вызывает Throttling/OOMKilled?
3. Что будет, если у пода заданы только `requests`, но не `limits`? Какой будет QoS-класс?
4. Почему QoS класс не указывается напрямую в `pod.yaml`?

---

## Часть 3: PriorityClass и Вытеснение (Preemption)

### Теория для изучения перед частью

- **`PriorityClass`** — это кластерный ресурс, задающий целочисленное значение важности (уровень приоритета). Чем больше число (поле `value`), тем важнее под.
- Поды ссылаются на приоритет через поле `priorityClassName`.
- **Preemption (вытеснение)** — это активный механизм планировщика (kube-scheduler). 

Если важному (High-prio) поду **НЕ ХВАТАЕТ** места ни на одной ноде, планировщик ищет ноду, где можно **ВЫСЕЛИТЬ (Preempt)** менее важные поды, чтобы освободить место.

> Отличие от QoS Eviction:
> - **Eviction (выселение по нехватке):** Нода реально переполнена, Kubelet убивает поды, чтобы спасти саму ноду от падения ядра. Работает реактивно на основе QoS.
> - **Preemption (вытеснение по приоритету):** Scheduler ещё только *планирует* новый под, но места нет. Он удаляет менее важные поды проактивно, чтобы дать место более важному. Работает на основе PriorityClass.

В Kubernetes есть системные приоритеты, например `system-cluster-critical` (value=2000000000) и `system-node-critical`. Их получают поды вроде `kube-proxy`, `coredns` или `calico-node`. Вытеснить их практически невозможно.

### 3.1 Как работает PriorityClass

Создадим два приоритета: `lab-low` и `lab-high`.

```yaml
# manifests/priorityclasses.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: lab-low
value: 100
globalDefault: false
description: "Низкий приоритет для фоновых задач"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: lab-high
value: 1000
globalDefault: false
description: "Высокий приоритет для критичных подов"
```

### 3.2 Подготовка ноды для детерминированного вытеснения

Чтобы вытеснение гарантированно произошло у нас на глазах, мы привяжем все наши демо-поды к одной конкретной воркер-ноде (с помощью label и `nodeSelector`). Так планировщик не сможет "сбежать" на другую свободную ноду.

```bash
# Находим первую попавшуюся worker-ноду
NODE=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')

# Размечаем ноду меткой lab-prio=target
kubectl label node "$NODE" lab-prio=target --overwrite
echo "Target node is $NODE"

# Применяем PriorityClasses
kubectl apply -f manifests/priorityclasses.yaml
```

### 3.3 Заполнение ноды low-prio подами

Запустим `Deployment` с классом `lab-low` (value=100), который "съест" большую часть ресурсов ноды.

```bash
# Применяем Deployment из 3-х реплик, каждая просит по 300m CPU
k apply -f manifests/low-prio.yaml

# Ждем запуска
k rollout status deploy/lab-low-app --timeout=90s

# Проверяем, что все 3 реплики работают на нашей target-ноде
k get pods -l app=lab-low-app -o wide
```

Если у ноды `allocatable CPU ~1400m`, то 3 пода по `300m` займут `900m`. С учётом системных демонов (Calico, kube-proxy), на ноде останется менее `300m` свободного CPU.

### 3.4 Демонстрация: High-prio вытесняет low-prio

Теперь мы пытаемся запустить один важный под (`lab-high-pod`) с приоритетом `lab-high` (value=1000), которому тоже нужно `300m` CPU.

```bash
k apply -f manifests/high-prio.yaml
```

Что произойдет?
1. `kube-scheduler` попробует разместить `lab-high-pod`. Места нет!
2. Планировщик увидит, что на ноде есть поды `lab-low-app` с приоритетом 100, что меньше 1000.
3. Он **выселит (delete)** один из подов `lab-low-app`.
4. `lab-high-pod` запустится на освободившемся месте.
5. Выселенный `lab-low-app` попытается запуститься снова, но останется в `Pending`.

Проверим это в реальном времени:

```bash
sleep 8 # Даем планировщику время

# High-prio под успешно запущен:
k get pod lab-high-pod

# А вот один из low-prio подов висит в Pending!
k get pods -l app=lab-low-app
```

Ожидаемый вывод:
```text
NAME                           READY   STATUS    RESTARTS
lab-low-app-5b68f5c94-7xxyz    1/1     Running   0
lab-low-app-5b68f5c94-8nqw2    1/1     Running   0
lab-low-app-5b68f5c94-abcde    0/1     Pending   0
```

### 3.5 Анализ событий вытеснения (Preempted)

Чтобы точно убедиться, что под был вытеснен именно механизмом Priority, посмотрим события кластера:

```bash
k get events | grep -i preempt
```

Вы увидите сообщение от `default-scheduler`:
`Normal Preempted pod/lab-low-app-... Preempted by lab/lab-high-pod on node k8s-w-1`

Это нормальное, ожидаемое поведение (by design). Если вы видите поды в `Pending`, всегда проверяйте события — возможно, их законно вытеснил кто-то более важный.

```bash
# Очистим ресурсы после эксперимента, чтобы освободить ноду:
k delete deploy lab-low-app pod lab-high-pod --ignore-not-found
kubectl label node "$NODE" lab-prio-
```

**Контрольные вопросы (Часть 3):**
1. В чём разница между Eviction из-за переполнения ноды и Preemption?
2. Кто осуществляет Preemption: Kubelet или kube-scheduler?
3. Какой PriorityClass назначен подам CoreDNS по умолчанию?
4. Что означает событие `Preempted by...` в логах кластера?

---

## Часть 4: LimitRange и ResourceQuota: Защита кластера

### Теория для изучения перед частью

Когда разработчики создают поды без `requests/limits`, они становятся классом `BestEffort`. С одной стороны, это плохо для стабильности самого приложения. С другой стороны, если под начнёт течь по памяти, он может забрать всю память ноды и спровоцировать системный OOM.

Чтобы защитить кластер, администраторы используют два механизма:
1. **LimitRange**: автоматическая подстановка дефолтных `requests` и `limits` в новые поды неймспейса, а также ограничение минимальных/максимальных размеров.
2. **ResourceQuota**: жесткий потолок на то, сколько **всего** ресурсов (CPU, Memory, томов, реплик) может запросить весь Namespace суммарно.

### 4.1 Установка дефолтных лимитов через LimitRange

Давайте применим LimitRange:

```yaml
# manifests/limitrange.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: lab-limits
  namespace: lab
spec:
  limits:
  - default:          # дефолтные limits
      cpu: 500m
      memory: 256Mi
    defaultRequest:   # дефолтные requests
      cpu: 100m
      memory: 128Mi
    type: Container
```

```bash
k apply -f manifests/limitrange.yaml
```

Теперь, если мы создадим под без ресурсов (BestEffort):

```bash
k run no-limits --image=busybox:1.36 -- sleep 3600
k get pod no-limits -o yaml | grep -A5 resources:
```

Вы увидите, что `LimitRange` сработал как Admission Controller и автоматически вставил ресурсы:
```yaml
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 100m
        memory: 128Mi
```
Благодаря этому под стал классом `Burstable` вместо `BestEffort` и больше не угрожает стабильности узла!

### 4.2 Защита неймспейса через ResourceQuota

Квоты защищают от злоупотребления ресурсами кластера на уровне команды или проекта.

```yaml
# manifests/quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: lab-quota
  namespace: lab
spec:
  hard:
    requests.cpu: "2"     # Не более 2 ядер запросов на весь NS
    requests.memory: 2Gi  # Не более 2 гигабайт
```

```bash
k apply -f manifests/quota.yaml

# Посмотреть текущее состояние квоты
k describe quota lab-quota
```

Если попытаться создать Deployment, который просит суммарно больше квоты, ReplicaSet просто не сможет создать поды, выдавая событие `Forbidden: exceeded quota`. Это частая причина "молчаливых" `Pending` подов.

```bash
k delete pod no-limits --ignore-not-found
```

---

## Часть 5: Enforcement лимитов — CPU throttle vs Memory OOM

### Теория для изучения перед частью

- **Enforcement (принуждение)** — механизм, через который ядро заставляет процесс соблюдать его `limits`.
- **CPU (Throttling)**: cgroups ограничивает процессорное время (bandwidth control). Метрика `container_cpu_cfs_throttled_seconds_total` в Prometheus показывает, сколько секунд процесс "проспал" из-за троттлинга. Это не убивает под, но сильно увеличивает задержки (latency) приложения.
- **Memory (OOM)**: cgroups отправляет OOMKiller. В логах пода вы не увидите ошибок приложения — ядро убивает его мгновенно. 

### 5.1 CPU Throttle в действии

К сожалению, показать CPU Throttling в терминале без графиков сложно, но вы можете сэмулировать его с помощью утилиты `stress`.

Если вы запустите под с `limits.cpu: 100m` и заставите его считать хэши или майнить:
```yaml
containers:
- name: stress
  image: progrium/stress
  args: ["--cpu", "1"]
  resources:
    limits: { cpu: "100m" }
```
Процесс будет думать, что он работает на все 100% ядра, но снаружи вы увидите, что он потребляет ровно `100m` (1/10 ядра). Никаких рестартов или крэшей не будет.

### 5.2 OOMKilled в действии и методы починки

А вот с памятью всё иначе. Применим сломанный под из `broken/scenario-01/oom-pod.yaml`.

В этом поде приложение пытается выделить `~100Mi` памяти, но `limits.memory` установлен в смешные `32Mi`.

```bash
k apply -f broken/scenario-01/oom-pod.yaml
sleep 15 # Ждём, пока процесс выделит память

# Посмотрим статус
k get pod mem-hog
```

Вы увидите:
```text
NAME      READY   STATUS      RESTARTS   AGE
mem-hog   0/1     OOMKilled   1          15s
```

Kubernetes попытается перезапустить контейнер (статус сменится на `CrashLoopBackOff`), но он снова упадет.
Узнаем точную причину через jsonpath:

```bash
k get pod mem-hog -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
# OOMKilled
```

**Решение:**
Единственный способ починить `OOMKilled` — это поднять `limits.memory` (если это ожидаемый пик) или починить утечку памяти в самом приложении.

```bash
k delete pod mem-hog

# Применяем исправленный манифест с лимитом в 256Mi
k apply -f solutions/01-oom/oom-pod.yaml
sleep 10
k get pod mem-hog
```

Теперь под успешно работает в состоянии `Running`, так как ему хватает памяти!

---

## Часть 6: Troubleshooting — боевые инциденты

Давайте систематизируем подходы к решению проблем с ресурсами.

### Инцидент 1: Pod навсегда в Pending (Insufficient CPU/Memory)

**Симптом:** Под висит в статусе `Pending` часами.
**Диагностика:**
```bash
k describe pod <pod-name> | tail -n 10
```
Вы увидите событие `FailedScheduling` с текстом `0/3 nodes are available: 3 Insufficient cpu`.
**Причина:** Сумма запрашиваемых `requests.cpu` превышает `allocatable` остаток на всех доступных нодах.
**Решение:**
1. Снизить аппетиты пода (уменьшить `requests`).
2. Добавить новые воркер-ноды в кластер (Scale up).
3. Повысить приоритет пода (`PriorityClass`), чтобы он вытеснил "соседей".

### Инцидент 2: Приложение тормозит, но нода не загружена (CPU Throttling)

**Симптом:** Пользователи жалуются на таймауты и 504 ошибки. На графиках Grafana потребление CPU ноды всего 30%.
**Диагностика:**
Посмотрите метрику `CPU Throttling` в дашбордах Kubernetes (или выполните `kubectl top pod`). Вы увидите, что под упирается ровно в свой лимит (например, `200m`).
**Причина:** Под зажат жёсткими `limits.cpu`, а ядру приложения требуется больше для обработки пиковых RPS.
**Решение:** Увеличить `limits.cpu`. В некоторых компаниях вообще убирают `limits.cpu` (оставляя только `requests`), доверяя CFS балансировку свободного времени.

### Инцидент 3: OOMKilled (Exit Code 137)

**Симптом:** Под постоянно уходит в `CrashLoopBackOff` с `OOMKilled`.
**Диагностика:**
События пода (`k describe pod`) покажут `Reason: OOMKilled`.
**Причина:** Контейнер превысил жесткий лимит памяти. Часто возникает в Java-приложениях с неправильно настроенным `-Xmx` (heap), или в Python/Node.js при утечках.
**Решение:** Увеличить `limits.memory` ИЛИ настроить рантайм языка программирования под существующий лимит (например, `-XX:MaxRAMPercentage=75.0`).

### Инцидент 4: Неожиданное выселение подов (Evicted)

**Симптом:** В выводе `kubectl get pods` появляются поды со статусом `Evicted`.
**Диагностика:**
```bash
k describe pod <evicted-pod>
```
Вы увидите сообщение `The node was low on resource: memory`.
**Причина:** На ноде случился перерасход (Overcommit) памяти, и Kubelet начал выселять поды `BestEffort` и `Burstable` для спасения системы.
**Решение:** Назначить критичным подам `Guaranteed` класс. Повысить общую ёмкость нод. Пересмотреть объемы Overcommit (увеличить `requests`).

---

## Проверка модуля

Запустите автоматическую проверку для подтверждения успешного прохождения модуля. Скрипт проверит состояние квот, применение LimitRange и наличие приоритетных классов.

```bash
bash verify/verify.sh
```

Ожидаемый вывод:
```text
✅ [OK] QoS classes and LimitRange applied correctly
✅ [OK] PriorityClasses verified
✅ [OK] ResourceQuotas configured
✅ [OK] Module 12 verified
```

---

## Финальная карта ресурсов модуля

| Концепция / Ресурс | Роль | Пример из лабы |
|--------------------|------|----------------|
| `requests` | Гарантия планирования | `100m` CPU, нужно для HPA и Scheduling |
| `limits` | Жесткий потолок cgroups | `256Mi` MEM, причина Throttling и OOMKilled |
| `QoS-класс` | Порядок выселения (Eviction) | Guaranteed, Burstable, BestEffort |
| `PriorityClass` | Приоритет вытеснения (Preemption) | `lab-low` (100) вытесняется `lab-high` (1000) |
| `LimitRange` | Дефолтные лимиты Namespace | Подстановка ресурсов в "пустые" поды |
| `ResourceQuota` | Защита квот на команду | Блок на >2Gi памяти в Namespace |

---

## Теоретические вопросы (итоговые)

### Блок 1: Requests, Limits и cgroups
1. Что именно проверяет kube-scheduler при поиске ноды для нового пода: requests или limits?
2. Какие механизмы ядра Linux (cgroups) отвечают за обеспечение limits для CPU и Памяти? В чем разница их поведения?
3. Что такое CPU Throttling и как он влияет на работу веб-сервиса?
4. Что означает Exit Code 137 у контейнера?

### Блок 2: QoS и Eviction
1. Каким правилам должен соответствовать под, чтобы получить класс `Guaranteed`?
2. В каком порядке Kubelet выселяет поды при исчерпании памяти на узле (Node-pressure)?
3. Какая разница между OOMKilled и Evicted? Кто их вызывает (ядро или Kubelet)?

### Блок 3: PriorityClass и Preemption
1. В чем принципиальное отличие `PriorityClass` (preemption) от `QoS` (eviction)?
2. Может ли планировщик вытеснить под с `PriorityClass` = 500, чтобы запустить под с `PriorityClass` = 100? А наоборот?
3. Что такое `system-node-critical` и зачем он нужен?

### Блок 4: Troubleshooting
1. Вы видите `Pending` под, а в events написано `FailedScheduling: Insufficient cpu`. Какой лимит нужно увеличить: кластера или пода?
2. Как LimitRange помогает администраторам избежать появления BestEffort подов в кластере?

---

## Чему вы научились

В этом модуле вы научились:
- Различать Requests и Limits, и понимать их влияние на планировщик и ядро Linux.
- Анализировать и предсказывать QoS-классы подов (Guaranteed, Burstable, BestEffort).
- Настраивать PriorityClasses для проактивного вытеснения (preemption) критически важных подов.
- Управлять ресурсами на уровне Namespace с помощью LimitRange и ResourceQuota.
- Диагностировать и исправлять ошибки `OOMKilled` и зависания по причине `CPU Throttling`.
- Анализировать причины `Pending` подов из-за нехватки вычислительных ресурсов.

---

## Уборка

Для очистки всех ресурсов, созданных в рамках этого модуля, запустите подготовленный скрипт (либо выполните команды вручную):

```bash
# Ручная очистка:
kubectl -n lab delete limitrange,resourcequota,deploy,pod --all --ignore-not-found
kubectl delete priorityclass lab-low lab-high --ignore-not-found
kubectl label node k8s-w-1 lab-prio- 2>/dev/null
kubectl label node k8s-w-2 lab-prio- 2>/dev/null

# Или скриптом:
bash verify/cleanup.sh
```

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами из шпаргалки.

1. Создайте `Deployment` из 5 реплик без указания ресурсов. Проверьте их QoS класс. Затем создайте `LimitRange`, удалите поды (чтобы они пересоздались) и проверьте их QoS класс снова. Он должен измениться.
2. Воспроизведите ситуацию `OOMKilled` самостоятельно: напишите простейший yaml с лимитом `10Mi` и образом `polinux/stress` (запустив `stress --vm 1 --vm-bytes 50M`).
3. Разметьте ноду, заполните её `low-prio` подами до предела `allocatable`. Создайте `high-prio` под и поймайте событие `Preempted` в логах кластера.
4. Настройте `ResourceQuota` в неймспейсе `default` на `1 CPU` и попытайтесь создать под с запросом `2 CPU`. Изучите полученную ошибку.

---

## Шпаргалка

```bash
# === Анализ потребления и лимитов ===
kubectl top nodes                                    # реальное потребление CPU/MEM узлами
kubectl top pods -n <namespace>                      # реальное потребление подами
kubectl describe node <node> | grep -A5 Allocated    # сколько requests зарезервировано

# === QoS и статусы ===
kubectl -n lab get pod <p> -o jsonpath='{.status.qosClass}'
kubectl -n lab get pod <p> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' # Поиск OOMKilled

# === Priority / preemption ===
kubectl get priorityclass
kubectl label node <worker> lab-prio=target --overwrite   # для демо preemption
kubectl -n lab get events | grep -i preempt
kubectl label node <worker> lab-prio-                     # снять метку

# === Troubleshooting квот и планировщика ===
kubectl -n lab describe quota                        # проверка остатков по квоте
kubectl -n lab describe limitrange                   # дефолты неймспейса
kubectl -n lab describe pod <p> | grep -A3 FailedScheduling # почему Pending
```
