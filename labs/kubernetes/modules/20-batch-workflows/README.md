# Лабораторная работа 20: Батч-нагрузки и workflows (Job parallelism, Indexed, podFailurePolicy, CronJob)

> ⏱ время ~20 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)

Цель: научиться запускать КОНЕЧНЫЕ задачи (в отличие от вечных сервисов) — через
`Job` с параллелизмом и фиксированным числом завершений, `Indexed`-партиционирование
работы, управление сбоями (`backoffLimit`, `podFailurePolicy`) и временем
(`activeDeadlineSeconds`, `ttlSecondsAfterFinished`, `suspend`), а также `CronJob`
по расписанию с политиками наложения. К концу модуля вы осознанно выбираете
параметры батч-задачи и диагностируете «Job завис / не завершился».

> Развитие модуля 03 (Job/CronJob — введение). Здесь — продвинутые батч-паттерны:
> параллелизм, шардирование, политики сбоев, расписания. Reconcile-петля Job-
> контроллера — та же модель, что в модуле 01.

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

## Часть 1: Job — parallelism и completions

### Теория для изучения перед частью

- **Job** запускает поды до УСПЕШНОГО завершения и считается выполненным, когда
  накопилось `completions` успешных подов. В отличие от Deployment, Job НЕ держит
  поды вечно — задача конечна.
- **`completions`** — сколько успешных подов нужно ВСЕГО. **`parallelism`** —
  сколько бежит ОДНОВРЕМЕННО. Их комбинация задаёт паттерн:

| `completions` | `parallelism` | Паттерн |
|---|---|---|
| N | 1 | последовательно N задач (по одной) |
| N | M (M<N) | N задач «волнами» по M (наш `job-parallel`: 6/2 = 3 волны) |
| не задан (1) | M | **work-queue**: M воркеров тянут из внешней очереди, пока та не пуста |

- **`restartPolicy`** в Job только `Never` или `OnFailure` (не `Always`):
  - `Never` — упавший под НЕ перезапускается, Job создаёт НОВЫЙ под (каждая
    попытка = отдельный под, удобно для разбора по логам);
  - `OnFailure` — kubelet перезапускает контейнер В ТОМ ЖЕ поде (растёт RESTARTS,
    подов меньше).
- **`backoffLimit`** (по умолч. 6) — сколько РЕТРАЕВ на уровне Job до признания
  провала. Между ретраями — экспоненциальная пауза (10s→20s→…, потолок 6 мин).

---

**Цель:** запустить параллельный Job и увидеть «волны» подов.

**Ресурс:** `manifests/parallel/job-parallel.yaml` (`completions: 6, parallelism: 2`).

---

### 1.1 Запуск и наблюдение волн

```bash
kubectl -n lab apply -f manifests/parallel/job-parallel.yaml

# В любой момент Running не больше 2 (parallelism) — остальные Pending/ещё не созданы
kubectl -n lab get pods -l job-name=job-parallel
# NAME                 READY   STATUS      RESTARTS   AGE
# job-parallel-aaaaa   1/1     Running     0          2s   <- волна 1
# job-parallel-bbbbb   1/1     Running     0          2s
# (через ~3с первые Completed, поднимаются следующие 2)

kubectl -n lab wait --for=condition=complete job/job-parallel --timeout=120s
kubectl -n lab get job job-parallel
# NAME           STATUS     COMPLETIONS   DURATION   AGE
# job-parallel   Complete   6/6           ~10s       15s
```

```bash
# Подтверждение через status: succeeded == completions, condition Complete
kubectl -n lab get job job-parallel \
  -o jsonpath='succeeded={.status.succeeded} conditions={.status.conditions[*].type}{"\n"}'
# succeeded=6 conditions=SuccessCriteriaMet Complete
```

**Контрольные вопросы:**
1. Чем `completions` отличается от `parallelism`?
2. Почему в Job нельзя `restartPolicy: Always`?
3. Что произойдёт при `completions: 6, parallelism: 6`?

---

## Часть 2: Indexed Job — партиционирование работы

### Теория для изучения перед частью

- **`completionMode: Indexed`** выдаёт каждому поду УНИКАЛЬНЫЙ индекс
  `0..(completions-1)` в переменной окружения `JOB_COMPLETION_INDEX` (и в hostname,
  и в аннотации `batch.kubernetes.io/job-completion-index`).
- Под сам решает, какую часть данных обработать ПО СВОЕМУ индексу — статическое
  шардирование без внешнего координатора/очереди. Классика: «партиция #index
  таблицы», «кусок файла N из M», «диапазон ключей по индексу».
- **NonIndexed** (по умолчанию) — поды взаимозаменяемы, индекса нет; подходит для
  work-queue, где задачи берутся из общей очереди.
- `completedIndexes` в статусе показывает, какие индексы уже успешно отработали
  (формат диапазонов: `0-3` или `0,2-4`).

---

**Цель:** раздать 4 шарда четырём подам по уникальному индексу.

**Ресурс:** `manifests/indexed/job-indexed.yaml` (`completionMode: Indexed`).

---

### 2.1 Запуск Indexed Job

```bash
kubectl -n lab apply -f manifests/indexed/job-indexed.yaml
kubectl -n lab wait --for=condition=complete job/job-indexed --timeout=120s

# Каждый под отработал СВОЙ индекс — пересечений нет:
kubectl -n lab logs -l job-name=job-indexed --prefix --tail=1 | sort
# [pod/job-indexed-0-...] shard 0 of 4 on job-indexed-0-...
# [pod/job-indexed-1-...] shard 1 of 4 on job-indexed-1-...
# [pod/job-indexed-2-...] shard 2 of 4 ...
# [pod/job-indexed-3-...] shard 3 of 4 ...
```

```bash
# Режим и завершённые индексы
kubectl -n lab get job job-indexed \
  -o jsonpath='mode={.spec.completionMode} indexes={.status.completedIndexes}{"\n"}'
# mode=Indexed indexes=0-3
```

> Имя пода Indexed-Job включает индекс (`job-indexed-2-xxxxx`) — в отличие от
> случайного суффикса обычного Job. По индексу под детерминированно «знает свою
> работу».

**Контрольные вопросы:**
1. Откуда под берёт свой номер шарда?
2. Чем Indexed отличается от NonIndexed по назначению?
3. Что покажет `completedIndexes`, если шард 2 ещё не завершился?

---

## Часть 3: Управление сбоями и временем

### Теория для изучения перед частью

- **`podFailurePolicy`** (GA 1.31) — реагировать на сбой ПО КОДУ ВЫХОДА или
  причине, а не вслепую жечь `backoffLimit`. Действия: `FailJob` (фатально —
  оборвать Job сразу), `Ignore` (не считать попытку в backoff), `Count` (как
  обычно). Пример: `FailJob` на `exit 42` (баг кода) и `Ignore` на SIGTERM от
  вытеснения ноды (инфраструктурный сбой, не вина задачи).
- **`activeDeadlineSeconds`** — жёсткий ТАЙМАУТ на весь Job: истёк — Job
  обрывается (`reason=DeadlineExceeded`), даже если поды ещё бегут. Перебивает
  `backoffLimit`.
- **`ttlSecondsAfterFinished`** — авто-удаление Job (и его подов) через N секунд
  ПОСЛЕ финиша. Без него завершённые Job копятся и засоряют namespace.
- **`suspend: true`** — пауза: контроллер не создаёт поды (а уже идущие — удаляет).
  Снять (`suspend: false`) — Job продолжит. Удобно для «отложить до окна».

---

**Цель:** оборвать Job по «фатальному» коду, не тратя ретраи.

---

### 3.1 podFailurePolicy: fail-fast по коду выхода

```bash
kubectl -n lab apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: { name: failfast, namespace: lab }
spec:
  backoffLimit: 6                       # 6 ретраев... но политика оборвёт раньше
  podFailurePolicy:
    rules:
    - action: FailJob                   # на exit 42 -> немедленно провалить Job
      onExitCodes: { operator: In, values: [42] }
  template:
    spec:
      restartPolicy: Never
      containers:
      - { name: w, image: busybox:1.36, command: ["sh","-c","exit 42"] }
EOF
sleep 8

kubectl -n lab get job failfast \
  -o jsonpath='failed={.status.failed} reason={.status.conditions[*].reason}{"\n"}'
# failed=1 reason=PodFailurePolicy        <- ОДНА попытка, не 7; причина = политика
kubectl -n lab delete job failfast --ignore-not-found
```

> Без `podFailurePolicy` тот же `exit 42` израсходовал бы все 7 попыток
> (`reason=BackoffLimitExceeded`) — впустую, ведь баг кода ретраем не лечится.

### 3.2 suspend и ttlSecondsAfterFinished (фрагменты)

```bash
# Пауза Job на лету (поды удаляются, Job ждёт):
kubectl -n lab patch job job-parallel --type=merge -p '{"spec":{"suspend":true}}'
# Снять паузу:
kubectl -n lab patch job job-parallel --type=merge -p '{"spec":{"suspend":false}}'

# ttlSecondsAfterFinished уже стоит в наших Job (600с) — завершённый Job сам
# удалится через 10 мин, не оставляя мусора.
```

**Контрольные вопросы:**
1. Когда `FailJob` экономит ресурсы по сравнению с `backoffLimit`?
2. Зачем `ttlSecondsAfterFinished`, если Job и так завершился?
3. Что делает `suspend: true` с уже запущенными подами?

---

## Часть 4: CronJob — расписание и политики

### Теория для изучения перед частью

- **CronJob** создаёт по одному `Job` на каждый тик cron-расписания
  (`schedule: "*/1 * * * *"` — каждую минуту). `timeZone` задаёт пояс (GA 1.27;
  без него — UTC).
- **`concurrencyPolicy`** — что делать, если прошлый Job ещё бежит к новому тику:
  `Allow` (по умолч. — разрешить наложение), `Forbid` (пропустить новый),
  `Replace` (убить старый, запустить новый).
- **`startingDeadlineSeconds`** — если контроллер проспал тик дольше N секунд (был
  недоступен), НЕ запускать задним числом. Защита от «шторма» пропущенных запусков.
- **`successfulJobsHistoryLimit` / `failedJobsHistoryLimit`** — сколько прошлых Job
  хранить для разбора логов (по умолч. 3 и 1). Остальные подчищаются.

---

**Цель:** завести CronJob и увидеть порождённые Job.

**Ресурс:** `manifests/cron/cronjob.yaml` (`*/1`, `Forbid`, history-лимиты).

---

### 4.1 CronJob в действии

```bash
kubectl -n lab apply -f manifests/cron/cronjob.yaml
kubectl -n lab get cronjob batch-report
# NAME           SCHEDULE      TIMEZONE             SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# batch-report   */1 * * * *   Europe/Amsterdam     False     0        <none>          5s

# Подождать ~1-2 минуты — увидеть, что CronJob тикнул (LAST SCHEDULE заполнен):
kubectl -n lab get cronjob batch-report
# NAME           SCHEDULE      ...   LAST SCHEDULE   AGE
# batch-report   */1 * * * *   ...   30s             90s

# Job-ы создаются с именем batch-report-<unix-минуты>. ВАЖНО: на Job НЕТ метки
# cronjob-name — связь с CronJob идёт через ownerReferences и префикс имени,
# поэтому фильтруем по имени, а не `-l`:
kubectl -n lab get jobs | grep batch-report
# batch-report-29677031     Complete   1/1   ...

# Лог последнего запуска (по префиксу имени последнего Job):
LAST=$(kubectl -n lab get jobs -o name | grep batch-report | tail -1)
kubectl -n lab logs -l job-name="${LAST##*/}" --tail=1
# report generated at 2026-06-...Z
```

```bash
# Ручной запуск CronJob ВНЕ расписания (для теста, без ожидания тика):
kubectl -n lab create job --from=cronjob/batch-report report-manual
kubectl -n lab wait --for=condition=complete job/report-manual --timeout=60s
```

**Контрольные вопросы:**
1. Чем `Forbid` отличается от `Replace` в `concurrencyPolicy`?
2. Зачем `startingDeadlineSeconds`?
3. Как запустить CronJob немедленно, не дожидаясь расписания?

---

## Часть 5: Troubleshooting — боевые инциденты

### Теория: диагностика батч-задач

Батч-сбои сводятся к трём вопросам: Job не СТАРТУЕТ, не ЗАВЕРШАЕТСЯ или CronJob не
ТИКАЕТ. Дерево:

```
Job-проблема
│
├─ Job есть, подов НЕТ ────────► describe job → suspend:true? completions достигнуты?
│                                 либо quota/PSA не дают создать под (Events)
├─ Поды в Error, Job не Complete ► backoffLimit исчерпан?
│     describe job → reason=BackoffLimitExceeded; logs --previous = корень
│     (Сценарий 01). Фатальный код? → podFailurePolicy FailJob (Часть 3)
├─ Job висит, поды Running вечно ► нет условия выхода / activeDeadlineSeconds не задан
│     → задать deadline; проверить, что команда РЕАЛЬНО завершается (exit)
└─ CronJob не создаёт Job ───────► get cronjob: SUSPEND=True? LAST SCHEDULE?
      describe cronjob → "Cannot determine if job needs to be started"
      = startingDeadlineSeconds истёк / concurrencyPolicy=Forbid и прошлый завис
```

---

### Инцидент 1: Job не завершается — `BackoffLimitExceeded`

Оформлен как `broken/scenario-01/` (Job `job-flaky` с командой, читающей
несуществующий файл → `exit 1` → после `backoffLimit` Job `Failed`). Там —
полный цикл воспроизведение → диагностика → решение.

```bash
kubectl -n lab apply -f broken/scenario-01/job-broken.yaml
sleep 30
kubectl -n lab get job job-flaky
# job-flaky   Failed   0/1   ...
kubectl -n lab describe job job-flaky | grep -i backoff
# Warning  BackoffLimitExceeded  Job has reached the specified backoff limit
kubectl -n lab logs -l job-name=job-flaky --tail=1
# cat: can't open '/data/input.txt': No such file or directory

# Решение: исправить команду и ПЕРЕСОЗДАТЬ (template иммутабелен у Failed-Job)
kubectl -n lab delete job job-flaky
kubectl -n lab apply -f solutions/01-backoff/job-fixed.yaml
kubectl -n lab wait --for=condition=complete job/job-flaky --timeout=60s
```

### Бонус: быстрая диагностика батч

```bash
# Все Job и их статус
kubectl -n lab get jobs
# Незавершённые Job (active>0 долго) — кандидаты на зависание
kubectl -n lab get jobs -o custom-columns=NAME:.metadata.name,ACTIVE:.status.active,SUCC:.status.succeeded,FAIL:.status.failed
# События namespace (создание/провал подов Job)
kubectl -n lab get events --sort-by=.lastTimestamp | grep -iE "job|backoff|deadline" | tail -10
# Причина завершения Job (condition)
kubectl -n lab get job <job> -o jsonpath='{.status.conditions[*].type}:{.status.conditions[*].reason}{"\n"}'
```

---

## Проверка модуля

```bash
# Сначала разверните рабочие манифесты (не broken)
kubectl -n lab apply -f manifests/parallel/job-parallel.yaml
kubectl -n lab apply -f manifests/indexed/job-indexed.yaml
kubectl -n lab apply -f manifests/cron/cronjob.yaml

# Автопроверка
bash verify/verify.sh
# [OK] job-parallel completed all 6 completions
# [OK] job-indexed Indexed mode, completedIndexes=0-3
# [OK] cronjob/batch-report present (schedule: */1 * * * *)
# [OK] module 20 verified
```

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Роль |
|--------|-----|------|
| `job-parallel` | Job | completions 6 / parallelism 2 — волны подов |
| `job-indexed` | Job (Indexed) | 4 шарда по уникальному `JOB_COMPLETION_INDEX` |
| `batch-report` | CronJob | `*/1` + `Forbid` + history-лимиты |
| `job-flaky` | Job (broken→solution) | демонстрация `BackoffLimitExceeded` |
| `failfast` | Job (ad-hoc) | `podFailurePolicy: FailJob` на exit 42 |

---

## Теоретические вопросы (итоговые)

### Блок 1: Job, parallelism, completions
1. Когда `parallelism < completions` и что это даёт?
2. Почему в Job нет `restartPolicy: Always`?
3. Чем `Never` отличается от `OnFailure` по числу создаваемых подов?

### Блок 2: Indexed
4. Как под узнаёт свой индекс и где он ещё виден, кроме env?
5. Для какой задачи Indexed лучше, чем work-queue, и наоборот?

### Блок 3: Сбои и время
6. Чем `podFailurePolicy: FailJob` лучше, чем просто маленький `backoffLimit`?
7. Что перебьёт `backoffLimit` — `activeDeadlineSeconds` или наоборот?
8. Зачем `ttlSecondsAfterFinished`?

### Блок 4: CronJob
9. Три значения `concurrencyPolicy` — когда какое?
10. Что делает `startingDeadlineSeconds` после простоя контроллера?

---

## Практические задания (отработка)

См. подробные сценарии в `tasks/`:

1. **`tasks/01-parallel-completions.md`** — поиграть с `completions`/`parallelism`,
   увидеть волны и предельный параллелизм.
2. **`tasks/02-indexed-shards.md`** — Indexed Job, убедиться в уникальности индексов.
3. **`tasks/03-failure-and-cron.md`** — `podFailurePolicy: FailJob` + CronJob с
   `concurrencyPolicy` и ручным запуском.

Дополнительно:
4. Задайте `activeDeadlineSeconds: 5` на Job с `sleep 30` — поймайте
   `reason=DeadlineExceeded`.
5. Поставьте CronJob `concurrencyPolicy: Replace` с долгим Job — увидите, как новый
   тик убивает предыдущий незавершённый Job.

---

## Шпаргалка

```bash
# === Job: запуск/наблюдение ===
kubectl -n lab apply -f manifests/parallel/job-parallel.yaml
kubectl -n lab wait --for=condition=complete job/<job> --timeout=120s
kubectl -n lab get job <job> -o jsonpath='{.status.succeeded}/{.spec.completions}{"\n"}'
kubectl -n lab logs -l job-name=<job> --prefix --tail=1   # логи всех подов Job

# === Indexed ===
kubectl -n lab get job <job> -o jsonpath='{.spec.completionMode} {.status.completedIndexes}{"\n"}'

# === Сбои / время ===
# podFailurePolicy: action FailJob|Ignore|Count + onExitCodes/onPodConditions
# activeDeadlineSeconds: жёсткий таймаут Job; ttlSecondsAfterFinished: авто-уборка
kubectl -n lab patch job <job> --type=merge -p '{"spec":{"suspend":true}}'   # пауза

# === CronJob ===
kubectl -n lab get cronjob <cj>
kubectl -n lab create job --from=cronjob/<cj> <name>   # запуск вне расписания
# concurrencyPolicy: Allow|Forbid|Replace; startingDeadlineSeconds; *JobsHistoryLimit

# === Диагностика ===
kubectl -n lab describe job <job> | grep -iE "reason|backoff|deadline"
kubectl -n lab logs -l job-name=<job> --previous   # лог упавшей попытки

# === Развернуть/проверить/убрать модуль ===
kubectl -n lab apply -f manifests/parallel/ -f manifests/indexed/ -f manifests/cron/
bash verify/verify.sh
kubectl -n lab delete job,cronjob --all
```

---


## Чему вы научились

В этом модуле вы научились:
- Запуску параллельных и индексированных (Indexed) Job
- Настройке политик обработки ошибок (podFailurePolicy)
- Периодическим бэкапам и батч-задачам через CronJob

## Уборка

```bash
kubectl -n lab delete job,cronjob --all --ignore-not-found
# (наши Job имеют ttlSecondsAfterFinished — подчистятся и сами через 5-10 мин)
```

> Дальше по ROADMAP: **Argo Workflows** (DAG-пайплайны из шагов, артефакты,
> fan-out/fan-in) — надстройка над Job для многошаговых процессов; здесь — нативный
> батч-фундамент, на котором они строятся.
