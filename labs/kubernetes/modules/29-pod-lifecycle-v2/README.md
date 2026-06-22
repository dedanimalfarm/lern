# Лабораторная работа 29: Жизненный цикл пода v2 — native sidecars, scheduling gates, in-place resize

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Native sidecar-контейнеры (GA 1.33)](#-1-native-sidecar--ga-133)
  - [Теория для изучения перед частью](#----)
  - [1.1 Job с native sidecar](#11-job--native-sidecar)
- [Часть 2: Scheduling gates — отложенный старт (GA 1.30)](#-2-scheduling-gates----ga-130)
  - [Теория для изучения перед частью](#----)
  - [2.1 Gated под и снятие gate](#21-gated----gate)
- [Часть 3: In-place Pod resize — вертикальный скейл без рестарта (beta 1.33)](#-3-in-place-pod-resize------beta-133)
  - [Теория для изучения перед частью](#----)
  - [3.1 Resize без рестарта (reality на нашем кластере)](#31-resize---reality---)
  - [3.2 Поймать обе валидации (важно понять ограничения)](#32------)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: Job не завершается (sidecar-антипаттерн)](#-1-job---sidecar-)
  - [Troubleshooting — частые проблемы](#troubleshooting---)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Контрольные вопросы](#-)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~25 мин · сложность 3/5 · пререквизиты: модули 02, 12

Цель: освоить ТРИ современные возможности API пода (все GA/beta в свежих k8s),
которые меняют повседневные паттерны платформ: **native sidecar-контейнеры**
(GA 1.33), **scheduling gates** (GA 1.30) и **in-place Pod resize** (beta 1.33).
К концу модуля вы делаете лог-/прокси-агент корректным sidecar'ом, откладываете
старт пода до внешнего сигнала без busy-wait, и меняете ресурсы работающему поду
без пересоздания — и понимаете ограничения каждой фичи.

> Развитие модуля 02 (жизненный цикл, sidecar-таблица) и 12 (QoS/resize). Здесь —
> практика новых API на живом кластере. Все «ожидаемые выводы» сняты на нашем
> Kubespray (k8s v1.36.1) — фичи доступны штатно (sidecar GA 1.33, gates GA 1.30,
> resize beta 1.33; наш сервер ≥ всех этих версий).

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lab delete job,pod --all --ignore-not-found 2>/dev/null

# Проверка, что фичи доступны (сервер свежий):
kubectl version -o json | grep -m1 gitVersion       # "v1.36.1" — ≥ всех нужных GA
# Признак активного in-place resize: у работающего пода в статусе есть
# allocatedResources (увидим в Части 3).
```

---

## Стартовая проверка

```bash
kubectl -n lab get job,pod 2>&1 | head -1     # пусто — ок
# Эти три фичи НЕ требуют аддонов — только свежий kube-apiserver/kubelet.
```

---

## Часть 1: Native sidecar-контейнеры (GA 1.33)

### Теория для изучения перед частью

- **Sidecar** — вспомогательный контейнер рядом с приложением (лог-шиппер,
  service-mesh proxy, vault-agent, метрик-агент). Раньше его клали в `containers[]`
  — и в **Job** это ломалось: app отрабатывал, а вечный sidecar не давал поду
  завершиться (под висел `1/2 NotReady`, Job `active` навсегда).
- **Native sidecar** = `initContainer` с `restartPolicy: Always`. Поведение:
  - стартует в фазе init, но **НЕ блокирует** (как только `Started` — идут
    app-контейнеры; обычный init блокирует до `Completed`);
  - живёт весь срок пода рядом с app;
  - **гасится ПОСЛЕ** app-контейнеров (обратный порядок) — поэтому лог-/прокси-
    сайдкары успевают дослать данные при завершении;
  - в **Job** под завершается по выходу app-контейнеров — sidecar не держит Job.

---

**Цель:** native sidecar в Job, который корректно завершается.

**Ресурс:** `manifests/sidecar/job.yaml` (logshipper = init+`restartPolicy: Always`).

---

### 1.1 Job с native sidecar

```bash
kubectl -n lab apply -f manifests/sidecar/job.yaml

# Под 2/2 (sidecar + app работают рядом), затем app выходит -> под завершается
kubectl -n lab get pod -l job-name=sidecar-job -w
# sidecar-job-xxxxx   2/2   Running     0   3s
# sidecar-job-xxxxx   1/2   ...                      <- app завершён (Completed)
# sidecar-job-xxxxx   0/2   Completed   0   ~7s      <- sidecar погашен ПОСЛЕ app

kubectl -n lab wait --for=condition=complete job/sidecar-job --timeout=60s
kubectl -n lab get job sidecar-job
# NAME          STATUS     COMPLETIONS   DURATION
# sidecar-job   Complete   1/1           ~7s
```

```bash
# Подтверждение «нативности»: logshipper лежит в initContainers с restartPolicy:Always
kubectl -n lab get job sidecar-job \
  -o jsonpath='{.spec.template.spec.initContainers[0].name}: restartPolicy={.spec.template.spec.initContainers[0].restartPolicy}{"\n"}'
# logshipper: restartPolicy=Always
```

> Положите тот же logshipper в `containers[]` — и Job не завершится никогда
> (антипаттерн в `broken/scenario-01/`). Native sidecar решает ровно это.

**Контрольные вопросы:**
1. Чем native sidecar отличается от обычного init-контейнера по блокировке старта?
2. Почему sidecar в `containers[]` ломает Job?
3. В каком порядке гасятся app и sidecar при завершении пода?

---

## Часть 2: Scheduling gates — отложенный старт (GA 1.30)

### Теория для изучения перед частью

- **`schedulingGates`** — список «затворов» на поде. Пока есть хоть один gate,
  scheduler **игнорирует** под: фаза `Pending`, condition `PodScheduled=False`
  reason `SchedulingGated`. Под даже не рассматривается для размещения.
- Снять gate можно **только патчем** (удалить из списка). **Добавить** gate
  работающему/запланированному поду нельзя — только при создании.
- Зачем (вместо busy-wait в init-контейнере, который ест ресурсы): дождаться
  внешнего **approval**, **квоты** (так работает **Kueue** — придерживает поды
  gate'ом, пока в очереди не появится место), готовности зависимости, окна
  обслуживания. Под «спит» в API, не занимая ноду.

---

**Цель:** под висит `SchedulingGated`, пока gate не снят.

**Ресурс:** `manifests/gates/pod.yaml`.

---

### 2.1 Gated под и снятие gate

```bash
kubectl -n lab apply -f manifests/gates/pod.yaml
kubectl -n lab get pod gated-demo
# NAME         READY   STATUS    RESTARTS   AGE
# gated-demo   0/1     Pending   0          5s

kubectl -n lab get pod gated-demo -o jsonpath='phase={.status.phase} reason={.status.conditions[0].reason}{"\n"}'
# phase=Pending reason=SchedulingGated     <- НЕ «нет ресурсов», именно gate
```

```bash
# Снимаем gate (патч пустым списком) -> scheduler сразу берёт под
kubectl -n lab patch pod gated-demo --type=merge -p '{"spec":{"schedulingGates":[]}}'
sleep 5
kubectl -n lab get pod gated-demo
# gated-demo   1/1   Running   ...          <- поехал
```

**Контрольные вопросы:**
1. Чем `SchedulingGated`-Pending отличается от Pending из-за нехватки ресурсов?
2. Почему gate нельзя добавить уже запущенному поду?
3. Какой батч-менеджер использует gates под капотом и зачем?

---

## Часть 3: In-place Pod resize — вертикальный скейл без рестарта (beta 1.33)

### Теория для изучения перед частью

- **In-place resize** меняет `requests`/`limits` по CPU/памяти у **работающего**
  пода — без пересоздания (раньше любое изменение ресурсов = новый под).
- Делается через **subresource `resize`**: `kubectl patch pod X --subresource
  resize -p '{...}'`. Меняются **только cpu и memory**.
- **`resizePolicy`** на контейнере задаёт, нужен ли рестарт контейнера на изменение
  ресурса: `NotRequired` (применить на лету — типично для CPU) или
  `RestartContainer` (типично для памяти у приложений, что читают лимит на старте,
  напр. JVM `-XX:MaxRAMPercentage`).
- **`status.containerStatuses[].allocatedResources`** показывает, что kubelet
  РЕАЛЬНО выделил (может отставать от `spec` на время применения); `status.resize`
  отражает ход (`Proposed`/`InProgress`/`Deferred`/`Infeasible`).
- **Два жёстких ограничения** (ловят всех):
  1. **QoS-класс менять НЕЛЬЗЯ.** Если resize сделает requests==limits по всем
     ресурсам (Burstable→Guaranteed) или уберёт их — отказ.
  2. **requests ≤ limits** должно сохраняться.

---

**Цель:** поднять CPU работающему поду без рестарта; поймать обе валидации.

**Ресурс:** `manifests/resize/pod.yaml` (Burstable, `resizePolicy` cpu:NotRequired).

---

### 3.1 Resize без рестарта (reality на нашем кластере)

```bash
kubectl -n lab apply -f manifests/resize/pod.yaml
kubectl -n lab wait --for=condition=Ready pod/resize-demo --timeout=60s

kubectl -n lab get pod resize-demo -o jsonpath='ДО: req={.spec.containers[0].resources.requests.cpu} lim={.spec.containers[0].resources.limits.cpu} restarts={.status.containerStatuses[0].restartCount} alloc={.status.containerStatuses[0].allocatedResources.cpu}{"\n"}'
# ДО: req=100m lim=200m restarts=0 alloc=100m

# КОРРЕКТНЫЙ resize: поднимаем И requests, И limits (Burstable сохраняется):
kubectl -n lab patch pod resize-demo --subresource resize --type=strategic \
  -p '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"150m"},"limits":{"cpu":"300m"}}}]}}'
# pod/resize-demo patched
sleep 3

kubectl -n lab get pod resize-demo -o jsonpath='ПОСЛЕ: req={.spec.containers[0].resources.requests.cpu} lim={.spec.containers[0].resources.limits.cpu} restarts={.status.containerStatuses[0].restartCount} alloc={.status.containerStatuses[0].allocatedResources.cpu}{"\n"}'
# ПОСЛЕ: req=150m lim=300m restarts=0 alloc=150m     <- БЕЗ рестарта, kubelet применил
```

### 3.2 Поймать обе валидации (важно понять ограничения)

```bash
# (а) поднять ТОЛЬКО requests.cpu до limit (==) -> Burstable стал бы Guaranteed:
kubectl -n lab patch pod resize-demo --subresource resize --type=strategic \
  -p '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"300m"}}}]}}'
# Error ... Pod QOS Class may not change as a result of resizing

# (б) requests.cpu > limits.cpu:
kubectl -n lab patch pod resize-demo --subresource resize --type=json \
  -p '[{"op":"replace","path":"/spec/containers/0/resources/requests/cpu","value":"500m"}]'
# Error ... requests: Invalid value: "500m": must be less than or equal to cpu limit of 300m
```

> Память у нас `resizePolicy: RestartContainer` — resize памяти РЕСТАРТНЕТ контейнер
> (restarts+1), CPU `NotRequired` — на лету. Это сознательный выбор: многие рантаймы
> (JVM/Go GC) читают лимит памяти на старте.

**Контрольные вопросы:**
1. Через какой subresource делается in-place resize и какие ресурсы мутабельны?
2. Почему resize нельзя поменять QoS-класс пода?
3. Чем `NotRequired` отличается от `RestartContainer` в `resizePolicy`?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ Job не Complete, под 1/2 NotReady ──► «sidecar» в containers[] вместо native
│     (Сценарий 01). Проверь: kubectl get pod -o jsonpath ...containerStatuses
├─ Под Pending, reason=SchedulingGated ─► это НЕ нехватка ресурсов — на поде gate;
│     снять патчем schedulingGates:[]  (Часть 2)
└─ resize отбит ───────────────────────► читай текст ошибки:
      "QOS Class may not change"     -> resize меняет QoS (сделал requests==limits)
      "must be <= cpu limit"          -> requests > limits, подними и limit
      "only cpu and memory mutable"   -> патчишь не тот ресурс/поле
```

### Инцидент 1: Job не завершается (sidecar-антипаттерн)
Разобран в `broken/scenario-01/` (логгер в `containers[]` → Job висит). Решение —
сделать его native sidecar (`initContainers` + `restartPolicy: Always`).

### Troubleshooting — частые проблемы

1. **Job висит в состоянии Running бесконечно**
   - *Причина:* Скорее всего, sidecar-контейнер настроен как обычный контейнер в `containers`, а не `initContainer` с `restartPolicy: Always`.
   - *Решение:* Перенесите sidecar в `initContainers` и добавьте `restartPolicy: Always`.
2. **Pod завис в состоянии Pending с причиной SchedulingGated**
   - *Причина:* В спецификации пода указан массив `schedulingGates`, и он не пуст.
   - *Решение:* Снимите gate, отправив патч: `kubectl patch pod <name> --type=merge -p '{"spec":{"schedulingGates":[]}}'`.
3. **In-place resize выдаёт ошибку "Pod QOS Class may not change"**
   - *Причина:* Ваше изменение ресурсов приводит к изменению класса QoS (например, `requests` становятся равны `limits` по всем ресурсам).
   - *Решение:* Убедитесь, что после изменения класс QoS останется прежним (например, не делайте `requests` равными `limits`, если под был `Burstable`).

---

## Проверка модуля

```bash
kubectl -n lab apply -f manifests/sidecar/job.yaml
kubectl -n lab apply -f manifests/gates/pod.yaml
kubectl -n lab apply -f manifests/resize/pod.yaml

bash verify/verify.sh
# [OK] native sidecar: Job Complete, logshipper = init+restartPolicy:Always
# [OK] scheduling gate: gated-demo держится SchedulingGated до снятия gate
# [OK] in-place resize: resize-demo Ready, resizePolicy задан, allocatedResources.cpu=100m
# [OK] module 29 verified
```

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Демонстрирует |
|--------|-----|---------------|
| `sidecar-job` | Job | native sidecar (init+restartPolicy:Always), Job завершается |
| `gated-demo` | Pod | scheduling gate (Pending/SchedulingGated) |
| `resize-demo` | Pod | in-place resize (resizePolicy, allocatedResources) |

---

## Контрольные вопросы
1. В чём принципиальное различие между `initContainers` без `restartPolicy` и с `restartPolicy: Always` в контексте sidecar-паттерна?
2. Почему для изменения класса QoS пода (например, с Burstable на Guaranteed) недостаточно использовать in-place resize?
3. Каким образом scheduling gates помогают оптимизировать использование кластера по сравнению с init-контейнерами, которые просто ожидают (busy-wait)?
4. Как повлияет настройка `resizePolicy: RestartContainer` на работу контейнера при обновлении его `requests`/`limits` для памяти?

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-native-sidecar.md`** — native sidecar в Job vs антипаттерн.
2. **`tasks/02-scheduling-gates.md`** — gated под, снятие gate.
3. **`tasks/03-inplace-resize.md`** — resize без рестарта + поймать обе валидации.

Дополнительно:
4. Сделай resize ПАМЯТИ (`requests.memory`) и подтверди рестарт контейнера
   (`restarts` +1) из-за `resizePolicy: RestartContainer`.
5. Поставь два gate'а и сними их по одному — под поедет только когда снят последний.

---

## Шпаргалка

```bash
# === Native sidecar ===
# initContainers + restartPolicy: Always  (стартует не блокируя, гасится после app)
kubectl -n lab get job <j> -o jsonpath='{.spec.template.spec.initContainers[0].restartPolicy}'

# === Scheduling gates ===
kubectl -n lab get pod <p> -o jsonpath='{.status.conditions[0].reason}'   # SchedulingGated
kubectl -n lab patch pod <p> --type=merge -p '{"spec":{"schedulingGates":[]}}'   # снять

# === In-place resize ===
kubectl -n lab patch pod <p> --subresource resize --type=strategic \
  -p '{"spec":{"containers":[{"name":"<c>","resources":{"requests":{"cpu":"X"},"limits":{"cpu":"Y"}}}]}}'
kubectl -n lab get pod <p> -o jsonpath='{.status.containerStatuses[0].allocatedResources}{.status.resize}'
# правила: QoS не менять; requests<=limits; мутабельны только cpu/memory

# === Уборка ===
kubectl -n lab delete job,pod --all
```

---

## Чему вы научились
- Делать вспомогательные контейнеры **native sidecar**'ами, чтобы Job завершался и
  данные досылались при остановке.
- Откладывать старт пода через **scheduling gates** без busy-wait (основа Kueue).
- Менять ресурсы пода **на лету** (in-place resize), понимая ограничения QoS и
  requests≤limits и роль `resizePolicy`.

---

## Уборка

```bash
bash verify/cleanup.sh
```

> Дальше по дизайну v2-расширения (см. handoff NEW-MODULES-DESIGN.md): NM-3 DRA
> (устройства/GPU для AI), NM-4 Kueue/JobSet (батч с очередями) — где scheduling
> gates и sidecars работают «по-крупному».
