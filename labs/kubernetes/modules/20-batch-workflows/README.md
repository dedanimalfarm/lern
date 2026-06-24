# Лабораторная работа 20: Батч-нагрузки и workflows (Job parallelism, Indexed, podFailurePolicy, CronJob)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Архитектура и место батч-нагрузок в Kubernetes](#архитектура-и-место-батч-нагрузок-в-kubernetes)
  - [Жизненный цикл Job и Job Controller](#жизненный-цикл-job-и-job-controller)
  - [Под капотом: OwnerReferences и Labels](#под-капотом-ownerreferences-и-labels)
- [Часть 1: Job — parallelism и completions](#часть-1-job--parallelism-и-completions)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью)
  - [1.1 Запуск и наблюдение волн (Батч-процессинг)](#11-запуск-и-наблюдение-волн-батч-процессинг)
  - [Паттерн: Рабочая очередь (Work Queue)](#паттерн-рабочая-очередь-work-queue)
- [Часть 2: Indexed Job — партиционирование работы](#часть-2-indexed-job--партиционирование-работы)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-1)
  - [Архитектура статического шардирования (Indexed) vs Динамическая очередь (Work-Queue)](#архитектура-статического-шардирования-indexed-vs-динамическая-очередь-work-queue)
  - [2.1 Запуск Indexed Job](#21-запуск-indexed-job)
- [Часть 3: Управление сбоями и временем](#часть-3-управление-сбоями-и-временем)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-2)
  - [3.1 podFailurePolicy: fail-fast по коду выхода](#31-podfailurepolicy-fail-fast-по-коду-выхода)
  - [3.2 podFailurePolicy: Ignore для Spot инстансов (DisruptionTarget)](#32-podfailurepolicy-ignore-для-spot-инстансов-disruptiontarget)
  - [3.3 suspend и ttlSecondsAfterFinished (фрагменты)](#33-suspend-и-ttlsecondsafterfinished-фрагменты)
- [Часть 4: CronJob — расписание и политики](#часть-4-cronjob--расписание-и-политики)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-3)
  - [Нюансы расписания и часовых поясов](#нюансы-расписания-и-часовых-поясов)
  - [4.1 CronJob в действии](#41-cronjob-в-действии)
  - [Ручной запуск CronJob вне расписания (Ad-hoc)](#ручной-запуск-cronjob-вне-расписания-ad-hoc)
- [Часть 5: Troubleshooting — боевые инциденты](#часть-5-troubleshooting--боевые-инциденты)
  - [Теория: диагностика батч-задач](#теория-диагностика-батч-задач)
  - [Инцидент 1: Job не завершается — `BackoffLimitExceeded`](#инцидент-1-job-не-завершается--backofflimitexceeded)
  - [Инцидент 2: Зависший процесс и `activeDeadlineSeconds`](#инцидент-2-зависший-процесс-и-activedeadlineseconds)
  - [Инцидент 3: CronJob не запускает новые Job (эффект `Forbid`)](#инцидент-3-cronjob-не-запускает-новые-job-эффект-forbid)
  - [Инцидент 4: Ошибка `ImagePullBackOff` и исчерпание лимитов](#инцидент-4-ошибка-imagepullbackoff-и-исчерпание-лимитов)
  - [Инцидент 5: Контейнер падает с `OOMKilled`](#инцидент-5-контейнер-падает-с-oomkilled)
  - [Бонус: быстрая диагностика батч в одну строку](#бонус-быстрая-диагностика-батч-в-одну-строку)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
  - [Блок 1: Job, parallelism, completions](#блок-1-job-parallelism-completions)
  - [Блок 2: Indexed](#блок-2-indexed)
  - [Блок 3: Сбои и время](#блок-3-сбои-и-время)
  - [Блок 4: CronJob](#блок-4-cronjob)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
<!-- /TOC -->

> ⏱ время ~45 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)

Цель: научиться запускать КОНЕЧНЫЕ задачи (в отличие от вечных сервисов) — через
`Job` с параллелизмом и фиксированным числом завершений, `Indexed`-партиционирование
работы, управление сбоями (`backoffLimit`, `podFailurePolicy`) и временем
(`activeDeadlineSeconds`, `ttlSecondsAfterFinished`, `suspend`), а также `CronJob`
по расписанию с политиками наложения. К концу модуля вы осознанно выбираете
параметры батч-задачи и диагностируете «Job завис / не завершился».

> Развитие модуля 03 (Job/CronJob — введение). Здесь — продвинутые батч-паттерны:
> параллелизм, шардирование, политики сбоев, расписания. Reconcile-петля Job-
> контроллера — та же модель, что в модуле 01, но с фокусом на конечность жизненного цикла.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lab delete job,cronjob --all --ignore-not-found 2>/dev/null

# Версия кластера: podFailurePolicy GA с 1.31, Indexed GA с 1.24, CronJob timeZone
# с 1.27 — на нашем 1.36 всё доступно штатно.
kubectl version -o json | grep -m1 gitVersion
# "gitVersion": "v1.36.1"
```

---

## Стартовая проверка

```bash
# Чисто ли в namespace перед началом
kubectl -n lab get jobs,cronjobs
# No resources found in lab namespace.

# Ресурс batch/v1 — Job и CronJob в одной API-группе
kubectl api-resources --api-group=batch
# NAME       SHORTNAMES   APIVERSION   NAMESPACED   KIND
# cronjobs   cj           batch/v1     true         CronJob
# jobs                    batch/v1     true         Job
```

---

## Архитектура и место батч-нагрузок в Kubernetes

Kubernetes изначально проектировался для управления долгоживущими сервисами (Deployment, StatefulSet, DaemonSet), которые должны работать бесконечно и бесперебойно. Батч-нагрузки (Job, CronJob) имеют принципиально иную парадигму: их цель — **успешно завершить выполнение и остановиться, освободив ресурсы**.

### Жизненный цикл Job и Job Controller

Контроллер Job (Job Controller) работает в рамках `kube-controller-manager`. Его цикл примирения (reconcile loop) отличается от Deployment:
- **Deployment** стремится поддерживать заданное количество Pod'ов в состоянии `Running`. Если Pod завершается (даже с кодом 0), контроллер расценит это как потерю инстанса и создаст новый.
- **Job** стремится достичь заданного количества `completions` (успешных завершений Pod'ов). Если Pod завершается с кодом 0, контроллер фиксирует успех в `status.succeeded`, уменьшает количество оставшихся задач и приближает Job к состоянию `Complete`.

#### Визуализация конечного автомата Job Controller

```text
       [ Создание объекта Job ]
                  │
                  ▼
         [ Создание Pod(ов) ] ◄───────────────┐ 
                  │                           │
                  ▼                           │ Параллелизм (parallelism)
         [ Pod выполняет работу ]             │ определяет, сколько Pod'ов 
                  │                           │ могут находиться в статусе
        ┌─────────┴─────────┐                 │ Running одновременно.
        ▼                   ▼                 │
   [ exit 0 ]          [ exit >0 ]            │
        │                   │                 │
        │                   ▼                 │
        │             [ Pod Failed ]          │
        │                   │                 │
        │            (Проверка backoffLimit)  │
        │                   ├─────(Лимит не исчерпан)─────┘
        │                   │
        │                   ▼
        │            [ Job Failed ] 
        ▼
(Счётчик completions++)
        │
        ├─(completions < target)────┐
        │                           │
        ▼                           │
  [ Job Complete ] ◄────────────────┘
```

Разница между `restartPolicy: Never` и `restartPolicy: OnFailure` архитектурно важна:
- `Never`: При сбое контейнера (exit > 0) Pod переходит в терминальное состояние `Failed`. Job Controller видит это, увеличивает счётчик неудачных попыток и создаёт **совершенно новый Pod** на замену (с новым именем). Это оставляет в системе "трупы" (Failed Pods) для последующего анализа логов администратором.
- `OnFailure`: При сбое контейнера **Kubelet** (на самом узле) просто перезапускает контейнер внутри того же самого Pod'а. Новых Pod'ов в кластере не создаётся, у контейнера просто растёт счётчик `RESTARTS`. Job Controller в это время просто ждёт и не вмешивается.

### Под капотом: OwnerReferences и Labels

В отличие от Deployment, который ищет свои Pod'ы исключительно по `selector`, Job Controller использует гибридный подход:
1. При создании Job, контроллер автоматически генерирует уникальный label `controller-uid` (равный UID самого Job'а).
2. Этот label принудительно внедряется во все создаваемые Pod'ы.
3. Дополнительно контроллер прописывает `ownerReferences` в метаданных Pod'а, указывая на Job как на родителя.
4. Это гарантирует, что если вы создадите два Job'а с одинаковыми `matchLabels`, их Pod'ы никогда не перепутаются! (Deployment в такой ситуации начал бы удалять чужие Pod'ы).

---

## Часть 1: Job — parallelism и completions

### Теория для изучения перед частью

- **Job** запускает поды до УСПЕШНОГО завершения и считается выполненным, когда
  накопилось `completions` успешных подов. В отличие от Deployment, Job НЕ держит
  поды вечно — задача конечна.
- **`completions`** — сколько успешных подов нужно ВСЕГО. 
- **`parallelism`** — сколько бежит ОДНОВРЕМЕННО. 
  
Их комбинация задаёт паттерн работы:

| `completions` | `parallelism` | Паттерн | Сценарий использования |
|---|---|---|---|
| N | 1 | Sequential / Последовательный | Строго по одной задаче за раз, пока не наберется N. Идеально для последовательных миграций БД шаг за шагом. |
| N | M (M < N) | Волны / Батчи (Batching) | N задач выполняются "волнами" по M штук (например, 6 задач по 2 одновременно = 3 волны). Защита от перегрузки ресурсов. |
| 1 | 1 | Одиночный запуск | Разовая скриптовая задача (бэкап, репорт, инициализация схемы). |
| не задан | M | Work-Queue / Очередь | M воркеров работают параллельно, забирая задачи из внешней очереди (RabbitMQ, Redis). Как только очередь пуста, воркеры выходят с `exit 0`. |

- **`backoffLimit`** (по умолч. 6) — сколько РЕТРАЕВ на уровне Job разрешено до того, как весь Job будет признан провальным (Failed). Между ретраями выдерживается экспоненциальная пауза (10s → 20s → 40s → 80s → 160s → 320s), с потолком в 6 минут. Это защищает сторонние системы (например, API, к которому обращается Job) от DDoS-атаки упавшими подами.

---

**Цель:** запустить параллельный Job, увидеть «волны» подов и ограничение concurrency в действии.

---

### 1.1 Запуск и наблюдение волн (Батч-процессинг)

Представим, что у нас есть 6 пакетов данных для обработки. Мы не хотим запускать 6 подов сразу, чтобы не положить базу данных. Мы ограничим параллелизм двумя подами.

Создадим манифест:

```bash
cat <<EOF > /tmp/job-parallel.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: job-parallel
  namespace: lab
spec:
  completions: 6
  parallelism: 2
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: busybox:1.36
        command: ["sh", "-c", "echo 'Doing work...'; sleep 5; echo 'Done!'"]
EOF

kubectl -n lab apply -f /tmp/job-parallel.yaml
```

Давайте понаблюдаем за подами в динамике. Мы должны увидеть ровно 2 Running пода. Как только они завершатся (через 5 секунд), появятся следующие 2.

```bash
# В любой момент времени Running не больше 2 (согласно parallelism) — остальные ещё не созданы
kubectl -n lab get pods -l job-name=job-parallel
# Пример вывода в первые 5 секунд:
# NAME                 READY   STATUS      RESTARTS   AGE
# job-parallel-q8x2a   1/1     Running     0          2s   <- Волна 1
# job-parallel-f4m9z   1/1     Running     0          2s

# Через ~7 секунд:
# NAME                 READY   STATUS      RESTARTS   AGE
# job-parallel-q8x2a   0/1     Completed   0          7s
# job-parallel-f4m9z   0/1     Completed   0          7s
# job-parallel-k3l8p   1/1     Running     0          1s   <- Волна 2
# job-parallel-m9v2n   1/1     Running     0          1s
```

Дождемся полного завершения:

```bash
kubectl -n lab wait --for=condition=complete job/job-parallel --timeout=120s
kubectl -n lab get job job-parallel
# NAME           STATUS     COMPLETIONS   DURATION   AGE
# job-parallel   Complete   6/6           16s        16s
```

> **Важно:** Job-контроллер создаст ровно 6 подов. Никаких индексов или уникальных ID у подов нет (суффиксы случайны). В таком режиме поды должны сами знать, какую часть работы выполнять (например, атомарно брать задачу из БД `UPDATE tasks SET status='processing' WHERE status='new' LIMIT 1`).

### Паттерн: Рабочая очередь (Work Queue)

В режиме Work-Queue параметры `completions` не задаются вообще (подразумевается 1 успешное завершение Job целиком, а не подсчет подов). Мы задаем только `parallelism: M`.

В таком сценарии каждый Pod подключается к внешней очереди (RabbitMQ/Kafka/Redis), забирает сообщения и обрабатывает их. Как только очередь пустеет, Pod завершает работу (`exit 0`). Как только ЛЮБОЙ под успешно завершается, Job-контроллер больше не создает новые поды, а ждет завершения остальных. Когда все оставшиеся завершатся, Job переходит в `Complete`.

**Контрольные вопросы (Блок 1):**
1. Чем `completions` отличается от `parallelism` концептуально? В каких единицах они измеряются?
2. Почему в Job нельзя использовать `restartPolicy: Always`? Что бы произошло с логикой работы Job Controller'а, если бы Kubelet бесконечно поднимал успешно завершившийся скрипт?
3. Что произойдёт при конфигурации `completions: 6, parallelism: 6`?
4. Если `backoffLimit` установлен в 3, а pod падает 4 раза (exit 1), в каком статусе окажется Job? Продолжит ли он создавать поды?

---

## Часть 2: Indexed Job — партиционирование работы

### Теория для изучения перед частью

- **`completionMode: Indexed`** выдаёт каждому поду строго детерминированный, уникальный номер (индекс) от `0` до `(completions - 1)`. 
- Индекс инжектируется в Pod тремя способами одновременно:
  1. Переменная окружения `JOB_COMPLETION_INDEX`
  2. В имя хоста пода (hostname) и само имя ресурса Pod'а (например, `job-indexed-0-xxxxx`)
  3. В аннотацию пода `batch.kubernetes.io/job-completion-index`
- Это позволяет реализовать **статическое шардирование** данных без сложной инфраструктуры вроде брокеров сообщений.
- **NonIndexed** (по умолчанию) — поды взаимозаменяемы, индекса нет.
- `completedIndexes` в статусе Job показывает, какие именно индексы уже успешно отработали (формат диапазонов: `0-3` или `0,2,4-6`). Это позволяет Job Controller'у понимать, какой именно шард упал, и при ретрае создать Pod именно с тем `JOB_COMPLETION_INDEX`, который не удался, а успешные не трогать.

### Архитектура статического шардирования (Indexed) vs Динамическая очередь (Work-Queue)

```text
       INDEXED JOB (Статическое)                 WORK-QUEUE (Динамическое)
                                          
[ Под Index=0 ] ─► Читает Блок 0           [ Под A ] ─┐  
[ Под Index=1 ] ─► Читает Блок 1           [ Под B ] ─┼─► Тянут из RabbitMQ 
[ Под Index=2 ] ─► Читает Блок 2           [ Под C ] ─┘   до опустошения
                                           
+ Не нужна внешняя инфраструктура          + Авто-балансировка (быстрые поды 
+ Идеально для заранее известных блоков      возьмут больше задач)
+ Гарантия обработки каждого шарда ровно   + Обработка задач неизвестного 
  один раз (если скрипт идемпотентен)        объема
- Если Блок 1 огромный, Под 1 будет        - Нужен брокер сообщений (RabbitMQ)
  работать дольше всех (перекос)           - Сложная бизнес-логика в коде
```

---

**Цель:** раздать 4 шарда четырём подам по уникальному индексу, чтобы каждый выполнил свою эксклюзивную часть работы.

---

### 2.1 Запуск Indexed Job

```bash
cat <<EOF > /tmp/job-indexed.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: job-indexed
  namespace: lab
spec:
  completions: 4
  parallelism: 4
  completionMode: Indexed
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: busybox:1.36
        command:
        - "sh"
        - "-c"
        - |
          echo "I am pod with hostname: \$(hostname)"
          echo "My JOB_COMPLETION_INDEX is: \${JOB_COMPLETION_INDEX}"
          echo "Processing strictly shard \${JOB_COMPLETION_INDEX} out of 4"
          sleep 3
EOF

kubectl -n lab apply -f /tmp/job-indexed.yaml
kubectl -n lab wait --for=condition=complete job/job-indexed --timeout=120s
```

Посмотрим логи. Каждый под отработал СВОЙ индекс — пересечений нет:

```bash
kubectl -n lab logs -l job-name=job-indexed --prefix --tail=2 | sort
# [pod/job-indexed-0-xxxxx] My JOB_COMPLETION_INDEX is: 0
# [pod/job-indexed-0-xxxxx] Processing strictly shard 0 out of 4
# [pod/job-indexed-1-yyyyy] My JOB_COMPLETION_INDEX is: 1
# [pod/job-indexed-1-yyyyy] Processing strictly shard 1 out of 4
# [pod/job-indexed-2-zzzzz] My JOB_COMPLETION_INDEX is: 2
# [pod/job-indexed-3-wwwww] My JOB_COMPLETION_INDEX is: 3
```

Проверим режим и завершённые индексы в статусе ресурса Job:

```bash
kubectl -n lab get job job-indexed \
  -o jsonpath='mode={.spec.completionMode} indexes={.status.completedIndexes}{"\n"}'
# Ожидаемый вывод: mode=Indexed indexes=0-3
```

> **Важное отличие:** Имя пода Indexed-Job включает индекс вторым сегментом (`job-indexed-2-xxxxx`) — в отличие от случайного суффикса обычного Job. Это позволяет администраторам с первого взгляда понимать, какой шард упал, просто посмотрев `kubectl get pods`.

**Контрольные вопросы (Блок 2):**
1. Откуда под физически берёт свой номер шарда в коде (как достучаться)?
2. Представьте, что вы обрабатываете дамп базы данных, состоящий из 100 файлов `dump_00.sql` ... `dump_99.sql`. Как с помощью Indexed Job обработать их все параллельно без очереди? Напишите пример команды bash.
3. Что покажет `completedIndexes`, если поды 0, 1 и 3 завершились успешно, а шард 2 упал (exit 1) и сейчас перезапускается?

---

## Часть 3: Управление сбоями и временем

### Теория для изучения перед частью

Исторически батч-нагрузки в Kubernetes страдали от "слепоты": Job Controller не понимал, ПОЧЕМУ упал pod. Будь то баг в коде скрипта, или отключившийся узел кластера (Node Loss) — всё это считалось ошибкой и тратило драгоценный `backoffLimit`. В версиях 1.31+ ситуация кардинально изменилась.

- **`podFailurePolicy`** (GA в 1.31) — позволяет контроллеру реагировать на сбой ПО КОДУ ВЫХОДА (exit code) или по причинам (Pod Conditions). Возможные действия:
  - `FailJob` (фатально) — оборвать весь Job сразу, не тратя `backoffLimit`. Идеально для программных багов (например, `exit 42` = инвалидный конфиг, ретрай не поможет).
  - `Ignore` — проигнорировать падение и НЕ считать попытку в счётчик `backoffLimit`. Идеально для инфраструктурных сбоев (Node Eviction, OOMKilled инфраструктурный, Spot instance preempted). Попытка будет перезапущена бесплатно.
  - `Count` — считать попытку в `backoffLimit` (поведение по умолчанию, классический ретрай).
- **`activeDeadlineSeconds`** — жёсткий ТАЙМАУТ (в секундах) на весь жизненный цикл Job. Истёк таймаут — Job обрывается (`reason=DeadlineExceeded`), даже если поды ещё находятся в статусе Running. Это перебивает `backoffLimit` и защищает от бесконечно висящих (zombie) джобов с deadlock'ами.
- **`ttlSecondsAfterFinished`** — механизм авто-уборки. Удаляет Job (и его логи/поды) через N секунд ПОСЛЕ того, как он перешел в терминальное состояние (Complete/Failed). Без него завершённые Job копятся тысячами и засоряют etcd (базу данных кластера).
- **`suspend: true`** — пауза Job-контроллера. Контроллер не создает поды, а текущие удаляет. Снять паузу (`suspend: false`) — Job продолжит выполнение. Полезно для сложных Workflow-движков, которые готовят среду и снимают с паузы только когда данные готовы.

---

### 3.1 podFailurePolicy: fail-fast по коду выхода

Представим скрипт, который валидирует входные параметры. Если они неверны, скрипт выходит с кодом 42. Бессмысленно перезапускать скрипт с неверными параметрами 6 раз с экспоненциальной паузой — это тратит время и ресурсы. Мы хотим упасть немедленно!

```bash
cat <<'EOF' > /tmp/failfast.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: failfast
  namespace: lab
spec:
  backoffLimit: 6                       # Стандартные 6 ретраев
  podFailurePolicy:
    rules:
    - action: FailJob                   # Немедленно провалить Job!
      onExitCodes:
        operator: In
        values: [42]                    # Если контейнер вышел с кодом 42
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: busybox:1.36
        command: ["sh","-c","echo 'Checking config...'; sleep 2; echo 'Fatal error 42'; exit 42"]
EOF

kubectl -n lab apply -f /tmp/failfast.yaml
sleep 8

# Проверим статус Job:
kubectl -n lab get job failfast \
  -o jsonpath='failed={.status.failed} reason={.status.conditions[*].reason}{"\n"}'
# Ожидаемый результат: failed=1 reason=PodFailurePolicy
```

> **Разбор:** Без `podFailurePolicy` тот же `exit 42` израсходовал бы все 7 попыток (1 попытка + 6 ретраев `backoffLimit`), что заняло бы несколько минут из-за экспоненциального бэкоффа. Здесь же контроллер мгновенно увидел код 42 и перевел Job в статус Failed с причиной `PodFailurePolicy`.

Очистим эксперимент:
```bash
kubectl -n lab delete job failfast --ignore-not-found
```

### 3.2 podFailurePolicy: Ignore для Spot инстансов (DisruptionTarget)

Что если pod был убит кластером, потому что Node, на котором он работал, был вытеснен (Preempted/Evicted) или это был Spot/Preemptible узел, который забрал облачный провайдер? Это не вина разработчика, и мы не хотим тратить `backoffLimit`.

В таком случае pod получит `Condition: DisruptionTarget`. Мы можем настроить Job игнорировать такие падения:

```yaml
# Пример манифеста (только для ознакомления, не запускаем)
spec:
  podFailurePolicy:
    rules:
    - action: Ignore
      onPodConditions:
      - type: DisruptionTarget    # Встроенный тип условия сбоя
        status: "True"
```
С таким правилом ваш Job может безопасно работать на самых дешевых Spot узлах — сколько бы узлов не отняли, Job будет перезапускаться бесконечно (пока не выполнится успешно или не истечет `activeDeadlineSeconds`), не истощая `backoffLimit`!

### 3.3 suspend и ttlSecondsAfterFinished (фрагменты)

Продемонстрируем паузу (Suspend) вживую. Создадим долгий Job:

```bash
cat <<EOF > /tmp/job-suspend.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: job-suspend
  namespace: lab
spec:
  completions: 1
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: w
        image: busybox:1.36
        command: ["sleep", "600"]
EOF
kubectl -n lab apply -f /tmp/job-suspend.yaml
```

Поставим Job на паузу на лету. В этот момент запущенные поды будут принудительно удалены, а сам Job перейдет в статус Suspended, ожидая лучших времен.
```bash
kubectl -n lab patch job job-suspend --type=merge -p '{"spec":{"suspend":true}}'

# Проверим статус Suspended
kubectl -n lab get job job-suspend -o custom-columns=NAME:.metadata.name,SUSPEND:.spec.suspend,PODS:.status.active
# NAME          SUSPEND   PODS
# job-suspend   true      <none>  <- Pod удалился!
```

Снимем паузу (Pod создастся заново и начнет работу с нуля):
```bash
kubectl -n lab patch job job-suspend --type=merge -p '{"spec":{"suspend":false}}'
kubectl -n lab delete job job-suspend
```

**Контрольные вопросы (Блок 3):**
1. В каком сценарии `FailJob` экономит ресурсы кластера по сравнению со стандартным поведением `backoffLimit`?
2. Почему падение узла (Node Crash) не должно учитываться в `backoffLimit` в идеальном production?
3. Зачем нужен `ttlSecondsAfterFinished`, если Job и так успешно завершился и его поды больше не потребляют CPU? Какую подсистему Kubernetes мы этим спасаем?

---

## Часть 4: CronJob — расписание и политики

### Теория для изучения перед частью

- **CronJob** — это контроллер более высокого уровня, который создает ресурсы `Job` строго по cron-расписанию (например, `schedule: "0 2 * * *"` — каждый день в 2:00 ночи).
- **`concurrencyPolicy`** — критически важная политика, решающая "конфликты наложений" (что делать, если прошлый Job ещё бежит, а по расписанию уже наступило время запускать новый):
  - `Allow` (по умолчанию) — разрешить наложение. Может привести к "смертельной спирали", когда тяжелые бэкапы наслаиваются друг на друга, полностью убивая кластер и диски.
  - `Forbid` — пропустить новый запуск, пока не завершится старый. Безопасно для эксклюзивных задач (миграции, бэкап базы). Новый тик будет просто проигнорирован.
  - `Replace` — жестко убить старый Job (и его поды), запустить новый. Удобно, если результат старого уже безнадежно устарел (например, синхронизация котировок валют каждую минуту — нет смысла доделывать прошлую, если прилетела новая).
- **`startingDeadlineSeconds`** — защита от «шторма пропущенных запусков». Если контроллер CronJob проспал свой тик (например, API-сервер был недоступен, или сам контроллер перезагружался) дольше N секунд, то он НЕ будет запускать Job задним числом. 
- **`successfulJobsHistoryLimit` / `failedJobsHistoryLimit`** — сколько прошлых ресурсов Job (и их подов) хранить для истории и разбора логов (по умолчанию 3 и 1).

### Нюансы расписания и часовых поясов
Исторически CronJob работал только в UTC, что вызывало огромные проблемы с переводами часов (Daylight Saving Time). В версии 1.27 GA вышел параметр `timeZone`. Теперь вы можете написать `timeZone: "Europe/Moscow"` и быть уверенными, что бэкап всегда произойдет в 2:00 ночи по местному времени, независимо от перевода часов в мире.

---

**Цель:** завести CronJob, увидеть порождённые им Job, и протестировать политики.

---

### 4.1 CronJob в действии

Создадим CronJob, который выполняется каждую минуту и строго запрещает наложения (`Forbid`):

```bash
cat <<EOF > /tmp/cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: batch-report
  namespace: lab
spec:
  schedule: "*/1 * * * *"
  timeZone: "UTC"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: reporter
            image: busybox:1.36
            command: ["sh", "-c", "echo 'report generated at \$(date)'; sleep 5"]
EOF

kubectl -n lab apply -f /tmp/cronjob.yaml
```

Посмотрим статус CronJob:
```bash
kubectl -n lab get cronjob batch-report
# NAME           SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# batch-report   */1 * * * *   UTC        False     0        <none>          5s
```

Подождём ~1-2 минуты, чтобы CronJob тикнул (поле `LAST SCHEDULE` заполнится временем последнего успешного триггера):
```bash
kubectl -n lab get cronjob batch-report
# NAME           SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# batch-report   */1 * * * *   UTC        False     0        30s             90s
```

> **ВАЖНЫЙ НЮАНС:** Job-ы, порожденные CronJob, создаются с именем `cronjobName-<unix-timestamp>`. На ресурсе Job **НЕТ** метки с именем CronJob! Связь между Job и CronJob осуществляется только через `ownerReferences` в метаданных Job'а. Поэтому искать порожденные джобы нужно через `grep`, а не через селектор `-l`:

```bash
kubectl -n lab get jobs | grep batch-report
# batch-report-28266324     Complete   1/1   ...
```

Посмотрим лог последнего успешного запуска:
```bash
LAST=$(kubectl -n lab get jobs -o name | grep batch-report | sort | tail -1)
# Извлекаем имя пода через owner-reference (или берем префикс Job'а)
kubectl -n lab logs -l job-name="${LAST##*/}" --tail=1
# report generated at Mon Jun ... UTC 2026
```

### Ручной запуск CronJob вне расписания (Ad-hoc)
Администраторам часто нужно протестировать CronJob прямо сейчас, не дожидаясь расписания (особенно если расписание — раз в месяц на 1-е число). Для этого существует механизм создания Job напрямую из шаблона CronJob:

```bash
kubectl -n lab create job --from=cronjob/batch-report report-manual
kubectl -n lab wait --for=condition=complete job/report-manual --timeout=60s
# job.batch/report-manual condition met
```

**Контрольные вопросы (Блок 4):**
1. В каком сценарии бизнес-логики `concurrencyPolicy: Replace` является единственным правильным выбором?
2. Представьте, что кластер был выключен на выходные, а CronJob настроен на бэкап каждый час. Вы включаете кластер в понедельник утром. Что произойдет, если `startingDeadlineSeconds` НЕ задан? И что произойдет, если он равен `3600`?
3. Каким образом Kubernetes понимает, какие старые Job-ы нужно удалить для соблюдения `successfulJobsHistoryLimit`?

---

## Часть 5: Troubleshooting — боевые инциденты

### Теория: диагностика батч-задач

Батч-сбои сводятся к трем основным паттернам: 
1. Job не **СТАРТУЕТ** (Pod'ы не появляются вовсе).
2. Job не **ЗАВЕРШАЕТСЯ** (упал с ошибкой и исчерпал лимит, либо висит бесконечно).
3. CronJob не **ТИКАЕТ** (Job'ы не порождаются по расписанию).

Дерево принятия решений для траблшутинга:

```text
Job-проблема
│
├─ Job есть, подов НЕТ ────────► describe job → suspend:true? completions уже достигнуты?
│                                 либо ResourceQuota/PSA не дают создать под (смотри Events)
├─ Поды в Error, Job не Complete ► backoffLimit исчерпан?
│     describe job → ищи Warning BackoffLimitExceeded;
│     Смотри логи упавшего пода (logs --previous, если restartPolicy:OnFailure).
│     Фатальный код ошибки? → настроить podFailurePolicy FailJob (Часть 3)
├─ Job висит, поды Running вечно ► нет условия выхода из скрипта / activeDeadlineSeconds не задан
│     → Задать deadline; проверить скрипт (может он ждет ввода из stdin?)
└─ CronJob не создаёт Job ───────► get cronjob: SUSPEND=True? LAST SCHEDULE давно в прошлом?
      describe cronjob → "Cannot determine if job needs to be started"
      = startingDeadlineSeconds истёк / concurrencyPolicy=Forbid и прошлый завис
```

Давайте разберем 5 реальных боевых инцидентов и способы их диагностики.

---

### Инцидент 1: Job не завершается — `BackoffLimitExceeded`

Самая частая проблема: внутри контейнера происходит логическая ошибка (например, нет нужного файла, или упала база данных), контейнер падает (exit > 0), контроллер пытается его перезапустить 6 раз, и в итоге Job переходит в статус Failed.

```bash
cat <<EOF > /tmp/job-broken.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: job-flaky
  namespace: lab
spec:
  backoffLimit: 2  # Специально маленький лимит для быстрого фейла в лабе
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: w
        image: busybox:1.36
        command: ["cat", "/data/non-existent-file.txt"]
EOF

kubectl -n lab apply -f /tmp/job-broken.yaml
```

Диагностика:
```bash
sleep 20
kubectl -n lab get job job-flaky
# NAME        STATUS   COMPLETIONS   DURATION   AGE
# job-flaky   Failed   0/1           20s        20s

# Почему Failed? Идем в events Job'а:
kubectl -n lab describe job job-flaky | grep -A 5 "Events:"
# Warning  BackoffLimitExceeded  Job has reached the specified backoff limit

# Ищем причину в логах пода. Так как restartPolicy: Never, мы ищем Failed поды:
POD=$(kubectl -n lab get pods -l job-name=job-flaky -o name | tail -1)
kubectl -n lab logs $POD
# cat: can't open '/data/non-existent-file.txt': No such file or directory
```

**Решение:** Исправить баг в коде или команде. **Критически важно:** нельзя просто `kubectl edit` и отредактировать команду у Failed Job. Спецификация (`template`) у Job почти полностью иммутабельна после создания. Нужно удалить старый Job и создать новый!
```bash
kubectl -n lab delete job job-flaky
```

---

### Инцидент 2: Зависший процесс и `activeDeadlineSeconds`

Процесс не падает (нет `exit > 0`), но и не завершается (например, бесконечный цикл `while true`, ожидание сетевого ответа без таймаута или deadlock). `backoffLimit` тут не поможет вообще. Job будет висеть неделями, занимая CPU и память.

```bash
cat <<EOF > /tmp/job-hang.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: job-hang
  namespace: lab
spec:
  activeDeadlineSeconds: 10  # ЖЕСТКО убить весь Job через 10 сек
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: w
        image: busybox:1.36
        command: ["sh", "-c", "echo 'Processing infinite loop...'; sleep 9999"]
EOF

kubectl -n lab apply -f /tmp/job-hang.yaml
```

Диагностика:
```bash
sleep 15
kubectl -n lab get job job-hang
# NAME       STATUS   COMPLETIONS
# job-hang   Failed   0/1

# Узнаем точную причину провала:
kubectl -n lab describe job job-hang | grep -i deadline
# Warning  DeadlineExceeded  Job was active longer than specified deadline

kubectl -n lab delete job job-hang
```
**Решение:** Всегда используйте `activeDeadlineSeconds` как страховку от зомби-процессов в production, особенно если Job обращается к внешним API.

---

### Инцидент 3: CronJob не запускает новые Job (эффект `Forbid`)

Вы настроили важные бекапы раз в минуту, но разработчики жалуются, что бэкапы перестали создаваться еще со вчерашнего дня. Расписание правильное, SUSPEND=False. В чем дело?

```bash
cat <<EOF > /tmp/cj-forbid.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-db
  namespace: lab
spec:
  schedule: "*/1 * * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
          - name: w
            image: busybox:1.36
            # Симуляция: База выросла, теперь бэкап занимает 3 минуты!
            command: ["sleep", "180"] 
EOF
kubectl -n lab apply -f /tmp/cj-forbid.yaml
```

Диагностика (через 2-3 минуты):
```bash
kubectl -n lab get cronjob backup-db
# ACTIVE=1. Новые Job НЕ появляются каждую минуту, хотя расписание "*/1 * * * *".
```
**Причина:** Политика `concurrencyPolicy: Forbid` строго блокирует создание новых инстансов Job, пока первый "долгий" бэкап не перейдет в Complete. Из-за того, что задача стала работать дольше интервала расписания, все последующие тики просто игнорируются (skipping).

**Решение:** Уменьшить время работы бэкапа (оптимизация), увеличить интервал расписания (schedule), или сменить политику на `Allow`/`Replace`, если это безопасно для данных.
```bash
kubectl -n lab delete cj backup-db
```

---

### Инцидент 4: Ошибка `ImagePullBackOff` и исчерпание лимитов

В имени образа или теге допущена опечатка. Как это влияет на логику Job Controller?

```bash
cat <<EOF > /tmp/job-image.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: job-image
  namespace: lab
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: w
        image: busybox:invalid-typo-tag
        command: ["echo", "hello"]
EOF
kubectl -n lab apply -f /tmp/job-image.yaml
```

Диагностика:
```bash
kubectl -n lab get pods -l job-name=job-image
# STATUS: ImagePullBackOff
```
**Архитектурный факт.** Ошибка скачивания образа (ImagePullBackOff) или запуска контейнера (CreateContainerConfigError) **не увеличивает** счётчик `backoffLimit`: контейнер технически не стартовал и не сделал `exit > 0`. Поэтому такой Job не упирается в `backoffLimit` и остаётся в состоянии Pending/ImagePullBackOff неограниченно долго.

**Решение:** Опечатки в манифестах лечатся удалением Job и созданием заново. И еще раз — всегда добавлять `activeDeadlineSeconds`, который убьет Job даже в статусе ImagePullBackOff.
```bash
kubectl -n lab delete job job-image
```

---

### Инцидент 5: Контейнер падает с `OOMKilled`

Контейнер Job запросил слишком много памяти для обработки большого массива и был убит OOM Killer ядром Linux.

С точки зрения Job Controller, `OOMKilled` — это обычное падение контейнера (терминальный статус, exit code 137). 
Это **считается в `backoffLimit`**. Если лимит не исчерпан, контроллер (или Kubelet при OnFailure) запустит Pod заново. Но так как объем данных не изменился, новый Pod снова упадёт с OOMKilled, пока не исчерпает `backoffLimit`.
Решение: Увеличить `resources.limits.memory` в спецификации или уменьшить объем батча для обработки (оптимизировать код).

---

### Бонус: быстрая диагностика батч в одну строку

```bash
# Все Job и их подробный статус. Удобно искать зависшие с ACTIVE > 0, которые долго не завершаются.
kubectl -n lab get jobs -o custom-columns=NAME:.metadata.name,ACTIVE:.status.active,SUCC:.status.succeeded,FAIL:.status.failed

# Последние батч-события namespace (ищем Backoff, DeadlineExceeded, PodFailurePolicy)
kubectl -n lab get events --sort-by=.lastTimestamp | grep -iE "job|backoff|deadline|policy" | tail -10

# Извлечь точную причину завершения конкретного Job (парсинг массива Conditions)
kubectl -n lab get job <job-name> -o jsonpath='{.status.conditions[*].type}:{.status.conditions[*].reason}{"\n"}'
```

---

## Проверка модуля

```bash
# Сначала разверните базовые рабочие манифесты (если удалили)
kubectl -n lab apply -f /tmp/job-parallel.yaml
kubectl -n lab apply -f /tmp/job-indexed.yaml
kubectl -n lab apply -f /tmp/cronjob.yaml

# Подождите завершения заданий:
kubectl -n lab wait --for=condition=complete job/job-parallel --timeout=120s
kubectl -n lab wait --for=condition=complete job/job-indexed --timeout=120s

# Самопроверка глазами:
# 1. job-parallel должен иметь 6 COMPLETIONS.
# 2. job-indexed должен иметь статус Complete и completedIndexes.
# 3. cronjob batch-report должен иметь заполненный LAST SCHEDULE.
```

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Роль и Особенности |
|--------|-----|------|
| `job-parallel` | Job | `completions: 6` / `parallelism: 2` — демонстрация "волн" для защиты от перегрузки |
| `job-indexed` | Job (Indexed) | 4 шарда. Каждый под получает инжект уникального `JOB_COMPLETION_INDEX` для статического шардирования |
| `batch-report` | CronJob | Запуск `*/1`, блокировка наложений `Forbid`, лимиты истории, timeZone |
| `job-flaky` | Job (Troubleshooting) | Инцидент 1: Логический сбой кода и обрыв по `BackoffLimitExceeded` |
| `job-hang` | Job (Troubleshooting) | Инцидент 2: Зависший бесконечный процесс и обрыв по аппаратному `activeDeadlineSeconds` |
| `failfast` | Job (Advanced) | Продвинутое использование `podFailurePolicy: FailJob` на конкретный `exit 42` |

---

## Теоретические вопросы (итоговые)

### Блок 1: Job, parallelism, completions
1. Когда `parallelism < completions` и что это даёт в реальном production кластере? (Подсказка: ресурсное голодание БД)
2. Почему в Job запрещено указывать `restartPolicy: Always`? Как это противоречит архитектурной сути объекта?
3. Чем `restartPolicy: Never` отличается от `OnFailure` по числу создаваемых объектов Pod? Что лучше выбрать, если вам важно потом анализировать логи каждой неудачной попытки в Kibana/Elasticsearch?

### Блок 2: Indexed
4. Перечислите 3 места (интерфейса), через которые конкретный контейнер внутри пода может узнать свой номер индекса в режиме Indexed.
5. Для какой реальной задачи (приведите пример) Indexed Mode подходит лучше, чем паттерн work-queue с RabbitMQ? В чем минусы Indexed режима?

### Блок 3: Сбои и время
6. В чём огромное преимущество использования `podFailurePolicy: FailJob` (по коду выхода) перед банальным выставлением `backoffLimit: 0`?
7. Что перебьёт — `backoffLimit`, который ещё не достигнут (например, упало 2 раза из 6), или истёкший глобальный `activeDeadlineSeconds`?
8. Чем грозит кластеру отсутствие `ttlSecondsAfterFinished`, если в нем работает 1000 крон-джобов в день? Что именно переполнится?

### Блок 4: CronJob
9. Три значения `concurrencyPolicy`. В какой бизнес-ситуации вы бы выбрали `Replace`, отбросив старые данные ради новых?
10. Как работает защита от шторма запусков (`startingDeadlineSeconds`)? Если кластер лежал неделю, попытается ли CronJob выполнить все пропущенные 168 часовых запусков сразу после включения?

---

## Практические задания (отработка)

1. **Волны и лимиты:** Создайте Job с `completions: 10`, `parallelism: 2`. Внутри контейнера сделайте `sleep 5`. Понаблюдайте за поведением волн через `watch kubectl get pods`. Измените (через `kubectl scale` или редактирование манифеста, если разрешено, либо удалите и пересоздайте) parallelism на 10 и посмотрите, как это повлияет на скорость обработки всего Job.
2. **Индексы в бою:** Напишите Indexed Job (`completions: 3`), где bash-скрипт проверяет свой `$JOB_COMPLETION_INDEX`. Если индекс равен 1, скрипт падает с `exit 1`. Остальные спят 10 секунд и успешно завершаются. Посмотрите на статус ресурса (`completedIndexes` в `kubectl get job -o yaml`). Вы увидите, что `completedIndexes` будет равен `0,2`.
3. **Гонка со временем:** Задайте `activeDeadlineSeconds: 5` на Job с `command: ["sleep", "30"]`. Дождитесь фейла и найдите точную причину (`DeadlineExceeded`) в описании Job (events).
4. **Наложение крон-джобов:** Создайте CronJob (`schedule: "* * * * *"`) с `concurrencyPolicy: Replace` и скриптом `sleep 120`. Посмотрите через 2 минуты, как контроллер жестко "убивает" предыдущий недоработавший Pod, чтобы освободить место для нового тика.

---

## Шпаргалка

```bash
# === Job: запуск/наблюдение ===
kubectl -n lab apply -f job.yaml
kubectl -n lab wait --for=condition=complete job/<job-name> --timeout=120s
kubectl -n lab get job <job-name> -o jsonpath='{.status.succeeded}/{.spec.completions}{"\n"}'
# Логи всех подов конкретного Job'а (очень полезно, если parallelism > 1)
kubectl -n lab logs -l job-name=<job-name> --prefix --tail=10   

# === Indexed ===
kubectl -n lab get job <job-name> -o jsonpath='{.spec.completionMode} {.status.completedIndexes}{"\n"}'

# === Сбои / время ===
# podFailurePolicy: action FailJob|Ignore|Count + onExitCodes/onPodConditions
# activeDeadlineSeconds: жёсткий таймаут Job (в секундах)
# ttlSecondsAfterFinished: авто-уборка мусора (в секундах) после перехода в Complete/Failed
# Пауза / снятие с паузы на лету
kubectl -n lab patch job <job-name> --type=merge -p '{"spec":{"suspend":true}}'   

# === CronJob ===
kubectl -n lab get cronjob <cj-name>
# Запуск Job вне расписания "прямо сейчас" (Ad-hoc)
kubectl -n lab create job --from=cronjob/<cj-name> <manual-job-name>   

# === Диагностика ===
kubectl -n lab describe job <job-name> | grep -iE "reason|backoff|deadline"
# Лог предыдущей упавшей попытки контейнера (работает для restartPolicy: OnFailure)
kubectl -n lab logs -l job-name=<job-name> --previous   
```

---

## Чему вы научились

В этом модуле вы продвинулись от простого "запустить скрипт" до осознанного управления батч-нагрузками enterprise-уровня. Вы научились:
- Глубоко понимать отличия reconcilation-петли Job Controller'а от Deployment'а.
- Контролировать нагрузку на кластер с помощью "волн" параллелизма (`parallelism < completions`).
- Разделять независимые задачи по шардам без внешних очередей с помощью паттерна `Indexed Job`.
- Изящно обрабатывать ошибки бизнес-логики (`podFailurePolicy`), не тратя ресурсы на бессмысленные ретраи, и игнорировать инфраструктурные сбои (Spot Instances).
- Защищать кластер от зомби-процессов (`activeDeadlineSeconds`) и утечек памяти (`ttlSecondsAfterFinished`).
- Управлять наложениями периодических задач (`CronJob concurrencyPolicy`) и часовыми поясами.
- Диагностировать 5 самых популярных боевых инцидентов с батч-задачами в production.

## Уборка

```bash
kubectl -n lab delete job,cronjob --all --ignore-not-found
# (Наши Job с настроенным ttlSecondsAfterFinished подчистились бы и сами через некоторое время)
```

> Дальше по ROADMAP: **Argo Workflows** (DAG-пайплайны из шагов, артефакты,
> fan-out/fan-in) — надстройка над Job для многошаговых процессов; здесь — нативный
> батч-фундамент, на котором они строятся.
