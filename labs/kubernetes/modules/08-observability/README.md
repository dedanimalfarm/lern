# Лабораторная работа 08: Наблюдаемость (events, conditions, logs, metrics)

> ⏱ время ~20 мин · сложность 2/5 · пререквизиты: Трек 1 (Core)

Цель: диагностировать деградации только средствами кластера — по событиям,
условиям, логам и базовым метрикам, без внешнего стека. К концу модуля вы
собираете линейный runbook инцидента и отличаете проблему приложения от
проблемы кластера.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl -n lab delete deploy,sts,ds,job,cronjob,svc,pvc,pod,ingress,netpol,cm,secret --all --ignore-not-found 2>/dev/null
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
```

---

## Стартовая проверка

```bash
# metrics-server нужен для `kubectl top` (Часть 3). На GKE он есть по умолчанию;
# на kind/minikube — ставится отдельно.
kubectl top nodes 2>/dev/null && echo "metrics-server: OK" || echo "metrics-server НЕ установлен — Часть 3 не отработает"
```

---

## Часть 1: Events и Conditions

### Теория для изучения перед частью

- **Events** — хронология того, что делал кластер с объектом (Scheduled,
  Pulled, Started, FailedScheduling, BackOff). Живут ~1 час, потом исчезают.
- **Conditions** — агрегированное текущее состояние ресурса (`Ready`,
  `Available`, `Progressing`) с `status`/`reason`/`message`. Это «итог», а
  events — «история».

- **Компакция events.** Повторяющиеся события (одинаковые `involvedObject` +
  `reason` + `message`) НЕ плодятся по одному — apiserver их СХЛОПЫВАЕТ: растёт
  поле `count`, а `firstTimestamp`/`lastTimestamp` держат диапазон. Поэтому в
  `describe` видно `Warning BackOff 5m (x12 over 8m)` — одно событие со счётчиком,
  а не 12 строк. TTL по умолчанию ~1ч (`--event-ttl` на apiserver) — events НЕ
  архив, а быстро тающая лента.

- **Каталог conditions по типам ресурсов** (что смотреть на чём):

| Ресурс | Ключевые conditions |
|--------|---------------------|
| Pod | `PodScheduled` → `Initialized` → `ContainersReady` → `Ready` (порядок «созревания») |
| Deployment | `Available` (есть min реплик), `Progressing` (идёт rollout) |
| Node | `Ready`, `MemoryPressure`, `DiskPressure`, `PIDPressure` |
| PVC/PV | не conditions, а `phase`: `Pending`/`Bound`/`Released` |

---

**Цель:** собрать таймлайн и текущее состояние demo-нагрузки.

**Ресурс:** `manifests/demo/deploy.yaml` (`obs-demo`, пишет структурированный лог).

---

### 1.1 Events и Conditions

```bash
kubectl -n lab apply -f manifests/demo/deploy.yaml
kubectl -n lab rollout status deploy/obs-demo --timeout=120s

# Conditions Deployment — агрегированное состояние
kubectl -n lab get deploy obs-demo -o jsonpath='{range .status.conditions[*]}{.type}={.status} ({.reason}){"\n"}{end}'
# Available=True (MinimumReplicasAvailable)
# Progressing=True (NewReplicaSetAvailable)

# Events пода — хронология (в хвосте describe)
kubectl -n lab describe pod -l app=obs-demo | sed -n '/Events:/,$p'
# Scheduled -> Pulled -> Created -> Started
```

**Контрольные вопросы:**
1. Чем `Events` отличаются от `Conditions`?
2. Почему events нельзя считать долговременным логом?
3. Что означает `Available=True` у Deployment?

---

## Часть 2: Логи

### Теория для изучения перед частью

- `kubectl logs` читает stdout/stderr контейнера. Полезные флаги: `--previous`
  (логи упавшего запуска), `-c <container>` (нужный контейнер), `--since`/`--tail`,
  `-f` (поток), `-l <selector>` (по подам).
- **Структурированные логи** (`key=value` или JSON) машинно-разбираемы — проще
  фильтровать и агрегировать.

**Откуда `kubectl logs` берёт данные (путь лога):**

```
контейнер: stdout/stderr
   │  пишет
   ▼
CRI (containerd) ──> файл на НОДЕ: /var/log/pods/<ns>_<pod>_<uid>/<container>/N.log
                          │
   kubectl logs ──> kube-apiserver ──> kubelet (на той ноде) ──> читает этот файл
```

- **`--previous` (`-p`).** Читает лог ПРЕДЫДУЩЕГО завершённого запуска контейнера
  (kubelet хранит его до удаления пода/ротации). Нужен при CrashLoop: обычный
  `logs` покажет НОВЫЙ (уже перезапущенный) контейнер, где причины падения нет.
  Не сработает, если предыдущего запуска не было или лог уже ротирован/контейнер
  жил доли секунды (тогда причину берут из `lastState.terminated`, см. Часть 4).
- **Ограничения `kubectl logs`.** (1) Логи живут С ПОДОМ — удалили под/ноду, логов
  нет (нет центрального хранилища). (2) Хранится только последняя ротация
  (`containerLogMaxSize` ~10Mi × `containerLogMaxFiles` ~5). (3) Нет поиска/
  агрегации по многим подам и времени. Для этого нужен лог-стек (Loki/ELK) —
  собирает логи с нод в БД ДО того, как под умрёт.

---

**Цель:** прочитать логи, в т.ч. упавшего контейнера.

---

### 2.1 Структурированные логи

```bash
kubectl -n lab logs deploy/obs-demo --tail=3
# ts=2026-06-02T...:00+00:00 level=info msg=heartbeat
# ts=2026-06-02T...:05+00:00 level=info msg=heartbeat

# Фильтрация по полю (плюс structured logging):
kubectl -n lab logs deploy/obs-demo --tail=20 | grep 'level=info'
```

### 2.2 Логи упавшего контейнера

```bash
# Для CrashLoop-пода обычный logs покажет НОВЫЙ запуск — нужен --previous:
# kubectl -n lab logs <pod> --previous
# (демонстрация — в Части 4, инцидент CrashLoopBackOff)
```

**Контрольные вопросы:**
1. Зачем `--previous` и когда обычный `logs` бесполезен?
2. Почему структурированные логи упрощают расследование?
3. Как прочитать логи конкретного контейнера в многоконтейнерном поде?

---

## Часть 3: Метрики (metrics-server, kubectl top)

### Теория для изучения перед частью

- **metrics-server** собирает CPU/RAM подов и нод и отдаёт их `kubectl top` и
  HPA. Это «здесь и сейчас», БЕЗ истории.
- Для истории/алертов/дашбордов нужен Prometheus + Grafana — metrics-server их не
  заменяет.

**Пайплайн метрик (откуда берётся `kubectl top`):**

```
kubelet/cAdvisor на КАЖДОЙ ноде (эндпойнт /metrics/resource)
        │  scrape ~15с
        ▼
metrics-server (агрегирует, держит В ПАМЯТИ только последние точки)
        │  регистрирует Metrics API
        ▼
metrics.k8s.io  ──>  kubectl top  /  HPA (Resource-метрики)
```

**metrics-server vs Prometheus** (часто путают — это РАЗНЫЕ инструменты):

| | metrics-server | Prometheus |
|---|---|---|
| Что отдаёт | CPU/RAM здесь-и-сейчас | временные ряды (история) |
| Хранение | в памяти, последние точки | TSDB на диске (дни/недели) |
| Метрики | только Resource (CPU/RAM) | любые (app, kube-state, node-exporter) |
| Запросы | нет, просто значения | PromQL |
| Потребители | `kubectl top`, HPA | дашборды, алерты, HPA (custom/external) |

**Три уровня Metrics API** (важно для HPA — модуль 11):

| API | Кто реализует | Что меряет | Пример |
|-----|---------------|------------|--------|
| `metrics.k8s.io` (Resource) | metrics-server | CPU/RAM подов/нод | `kubectl top`, HPA по CPU |
| `custom.metrics.k8s.io` (Custom) | Prometheus Adapter | app-метрики на k8s-объектах | HPA по RPS |
| `external.metrics.k8s.io` (External) | адаптер к внешней системе | вне кластера | HPA по длине очереди SQS |

#### Usage vs Requests vs Limits — три понятия, три источника

Самая частая путаница в сайзинге: три разных числа из трёх разных команд.
Их **нельзя смешивать**.

| Понятие | Что это | Откуда взять | На что влияет |
|---|---|---|---|
| **Usage** (факт) | сколько контейнер ПОТРЕБЛЯЕТ прямо сейчас | `kubectl top pod/node` (metrics-server) | ничего не гарантирует; меняется секунда-в-секунду |
| **Requests** (резерв) | сколько scheduler РЕЗЕРВИРУЕТ под Pod | `kubectl describe node` → Allocated resources; `describe pod` → Requests | **планирование**: Pod встанет на ноду, только если хватает свободных requests |
| **Limits** (потолок) | жёсткий предел: CPU троттлится, RAM ⇒ OOMKilled | `kubectl describe pod` → Limits; spec контейнера | **enforcement** на ноде через cgroup |

```
   0 ──── requests ──────── usage(сейчас) ──── limits ─────► ресурс
   │      (резерв,           (факт,            (потолок,
   │       для scheduler)     для top)          для cgroup)
   │
   usage может быть НИЖЕ requests (зря зарезервировано) или
   ВЫШЕ requests (burst в пределах limits) — это нормально.
```

**Reality на нашем кластере** (одна нода `k8s-w-1`, три источника, три числа):

```bash
# 1) USAGE — реальное потребление прямо сейчас
kubectl top node k8s-w-1
# k8s-w-1   169m (12%)   1156Mi (37%)        <- факт

# 2) REQUESTS/LIMITS — сумма по всем подам ноды (резерв и потолки)
kubectl describe node k8s-w-1 | sed -n '/Allocated resources/,/Events/p'
# cpu      Requests 390m (27%)   Limits 1 (71%)     <- зарезервировано 390m, потолок 1 ядро
# memory   Requests 380Mi (12%)  Limits 933Mi (30%)

# 3) Requests/Limits конкретного пода — из его spec
kubectl -n kube-system get pod <coredns-pod> \
  -o jsonpath='{.spec.containers[0].resources}'
# requests: cpu 100m / memory 70Mi    limits: memory 300Mi   <- CPU-лимита НЕТ
```

> Два вывода из реальных чисел:
> - **usage (169m) < requests (390m)**: резерв держится, даже если поды простаивают.
>   Scheduler считает по requests, не по факту — нода может «кончиться» по
>   requests, оставаясь почти пустой по usage (см. Pending в м06/м13).
> - **у coredns есть limit по памяти, но НЕТ по CPU.** Это намеренно: CPU-лимит
>   = троттлинг (латентность), память без лимита = риск выселить соседей. Частый
>   прод-паттерн — ставить requests=limits для памяти и не лимитировать CPU.
>   Связь: requests/limits → QoS-класс и OOMKilled (модуль 02 Часть 4, модуль 12).

---

**Цель:** снять текущую нагрузку.

---

### 3.1 kubectl top

```bash
kubectl top nodes
# NAME        CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# ...-b02f    120m         6%     780Mi           27%

kubectl top pods -n lab
# NAME            CPU(cores)   MEMORY(bytes)
# obs-demo-...    1m           2Mi
```

> Сразу после старта пода возможно `metrics not available yet` — metrics-server
> собирает данные с задержкой ~1-2 мин, просто подождите. Ошибка `Metrics API
> not available` (без "yet") означает, что metrics-server не установлен (типично
> для свежего kind); на GKE он есть из коробки.

**Контрольные вопросы:**
1. Что даёт `metrics-server` и чего он принципиально НЕ умеет?
2. Чем `kubectl top` отличается от `kubectl describe node` (Allocated resources)?
3. Зачем metrics-server нужен для HPA?

---

## Часть 4: Troubleshooting и runbook

### Теория: каталог состояний пода + механика back-off

Большинство инцидентов — это одно из типовых состояний. Распознал → знаешь первую
команду:

| Состояние | Что значит | Первая команда / где причина |
|-----------|------------|------------------------------|
| `Pending` | не запланирован | `describe pod` → Events: `FailedScheduling` (Insufficient cpu/taint) |
| `ContainerCreating` (надолго) | образ/том/секрет не готовы | `describe pod` → Events (pull/mount/secret) |
| `ErrImagePull`/`ImagePullBackOff` | образ не тянется | `describe` → имя/тег/registry/доступ |
| `CrashLoopBackOff` | контейнер падает и рестартует | `logs --previous`; `lastState.terminated` |
| `CreateContainerConfigError` | нет ConfigMap/Secret или невалид securityContext | `describe pod` → Events |
| `OOMKilled` (в `lastState`) | превышен `limits.memory` | `lastState.reason=OOMKilled` → поднять limit / чинить утечку |
| `Completed` / `Error` | контейнер ЗАВЕРШИЛСЯ (exit 0 / ≠0) | `exitCode` (норма для Job; беда для сервиса) |
| `Terminating` (зависло) | finalizer / долгий graceful | `describe` → `finalizers`, `terminationGracePeriodSeconds` |
| `Evicted` | вытеснен по давлению ноды | `describe node` → `DiskPressure`/`MemoryPressure` |

- **Back-off у CrashLoop растёт ЭКСПОНЕНЦИАЛЬНО:** kubelet рестартует упавший
  контейнер через `10s → 20s → 40s → 80s → 160s → 300s` и дальше держит ПОТОЛОК
  **300с (5 мин)**. Счётчик сбрасывается, если контейнер проработал стабильно
  ~10 мин. Поэтому `RESTARTS` растёт, а паузы между рестартами всё длиннее.
- **OOMKilled vs Evicted** (частая путаница): OOMKilled — cgroup убил ОДИН
  контейнер за превышение `limits.memory` (exit 137), под остаётся; Evicted —
  kubelet выселил ВЕСЬ под из-за нехватки ресурсов на НОДЕ (node pressure).

**Node-pressure eviction: пороги и порядок выселения по QoS.** Когда на ноде
кончается память/диск, kubelet сам выселяет поды, чтобы спасти ноду:

```
kubelet следит за сигналами: memory.available, nodefs.available, imagefs.available
   │
   ├─ SOFT threshold  ─► ставит condition (MemoryPressure) + ждёт evictionSoftGracePeriod,
   │                      затем выселяет ГРАЦИОЗНО (SIGTERM, grace)
   └─ HARD threshold  ─► выселяет НЕМЕДЛЕННО, без grace (защита ноды важнее)

Кого выселять первым (порядок жертв):
   1. BestEffort   (нет requests/limits)          ◄── ПЕРВЫЕ, всегда
   2. Burstable, чей usage ВЫШЕ requests          ◄── «перебравшие» свой резерв
   3. Burstable в пределах requests / Guaranteed  ◄── ПОСЛЕДНИЕ, только в крайнем случае
```

- **QoS определяет очередь на выселение** (а также cgroup OOM-score): `BestEffort`
  гибнет первым, `Guaranteed` (requests==limits) — последним. Это прямой довод
  ставить requests/limits критичным сервисам (модуль 02 — QoS, модуль 12).
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

## Уборка

```bash
kubectl -n lab delete -k manifests/
kubectl -n lab delete deploy obs-broken --ignore-not-found
```
