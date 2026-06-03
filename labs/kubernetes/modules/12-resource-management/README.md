# Лабораторная работа 12: Управление ресурсами (QoS, PriorityClass, preemption, limits)

Цель: научиться управлять тем, СКОЛЬКО ресурсов получают поды и КТО важнее при
нехватке — через `requests`/`limits` и QoS-классы, `PriorityClass` с вытеснением
(preemption) и понимание, чем CPU-throttling отличается от Memory-OOMKilled. К
концу модуля вы осознанно назначаете приоритеты, читаете причину `OOMKilled` и
видите preemption вживую.

> Развитие модулей 02 (requests/limits/QoS/OOM — введение) и 06 (ResourceQuota/
> LimitRange — лимиты на namespace). Здесь — приоритеты, вытеснение и enforcement.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl -n lab delete deploy,pod,priorityclass --all --ignore-not-found 2>/dev/null
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# Ёмкость нод (на ней строится демо preemption — Часть 2)
kubectl get nodes -l '!node-role.kubernetes.io/control-plane' \
  -o custom-columns='NODE:.metadata.name,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory' --no-headers
# k8s-w-1   1400m   3118188Ki      <- worker-ноды, ~1.4 CPU allocatable
# k8s-w-2   1400m   3118188Ki
```

---

## Часть 1: requests/limits и QoS-классы

### Теория для изучения перед частью

- **`requests`** — ГАРАНТИЯ: scheduler ищет ноду, где столько СВОБОДНО (резервирует);
  база для процента HPA. **`limits`** — ПОТОЛОК (cgroup не даёт превысить).
- **QoS-класс** присваивается АВТОМАТИЧЕСКИ по requests/limits и определяет порядок
  ВЫСЕЛЕНИЯ при нехватке памяти на ноде (node-pressure eviction):

| QoS | Условие | Выселяют |
|-----|---------|----------|
| `Guaranteed` | requests == limits по ВСЕМ ресурсам и контейнерам | последними |
| `Burstable` | requests/limits заданы, но не равны (или частично) | вторыми |
| `BestEffort` | requests/limits НЕ заданы вовсе | ПЕРВЫМИ |

```
память ноды под давлением -> kubelet выселяет: BestEffort -> Burstable -> Guaranteed
                                                («не жалко» -> ... -> «трогаем в последнюю очередь»)
```

---

**Цель:** увидеть, как класс зависит от requests/limits.

**Ресурс:** `manifests/qos.yaml` (три пода — по поду на класс).

---

### 1.1 Три класса

```bash
kubectl -n lab apply -f manifests/qos.yaml
for p in qos-guaranteed qos-burstable qos-besteffort; do
  kubectl -n lab get pod $p -o jsonpath="  $p -> {.status.qosClass}{'\n'}"; done
# qos-guaranteed -> Guaranteed      (requests==limits)
# qos-burstable  -> Burstable       (requests<limits)
# qos-besteffort -> BestEffort      (нет requests/limits)
```

> ✅ **Прогнано на Kubespray:** классы присвоены ровно по правилам. QoS НЕ задаётся
> руками — он ВЫВОДИТСЯ из resources. Хотите Guaranteed — поставьте requests==limits.

**Контрольные вопросы:**
1. Чем `requests` отличается от `limits` по смыслу для scheduler и cgroup?
2. Как определяется QoS-класс и на что он влияет?
3. Какой класс выселят первым при нехватке памяти на ноде и почему?

---

## Часть 2: PriorityClass и preemption (вытеснение)

### Теория для изучения перед частью

- **`PriorityClass`** — именованный уровень важности (число `value`). Под ссылается
  на него через `priorityClassName`. Чем больше value — тем важнее под.
- **Preemption (вытеснение):** если важному поду НЕ ХВАТАЕТ места, scheduler может
  ВЫСЕЛИТЬ (удалить) поды с МЕНЬШИМ приоритетом на подходящей ноде, чтобы освободить
  ресурсы. Управляется `preemptionPolicy` (`PreemptLowerPriority` по умолчанию /
  `Never` — ждать, но не вытеснять).
- **Приоритет ≠ QoS.** QoS — про порядок eviction при node-pressure; priority — про
  то, кого scheduler ВЫТЕСНИТ ради размещения более важного. Системные поды имеют
  очень высокий priority (`system-node-critical`).

```
нода полна low-prio подами:  [ low ][ low ][ low ]
приходит high-prio (не влезает) -> scheduler ВЫСЕЛЯЕТ один low:
                             [ low ][ HIGH ][ low ]   + вытесненный low -> Pending
```

---

**Цель:** заполнить ноду low-prio подами и увидеть, как high-prio вытесняет один.

**Ресурсы:** `manifests/{priorityclasses,low-prio,high-prio}.yaml`.

---

### 2.1 Подготовка: разметить ОДНУ ноду (детерминизм)

```bash
# Запиним демо на одну worker-ноду, чтобы арифметика была предсказуемой.
NODE=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
kubectl label node "$NODE" lab-prio=target --overwrite
echo "target node = $NODE"
```

### 2.2 Заполнить ноду low-prio

```bash
kubectl apply -f manifests/priorityclasses.yaml          # lab-low(100), lab-high(1000)
kubectl -n lab apply -f manifests/low-prio.yaml          # 3 x 300m CPU на target-ноде
kubectl -n lab rollout status deploy/lab-low-app --timeout=90s
kubectl -n lab get pods -l app=lab-low-app -o wide       # 3 Running на target-ноде
```

### 2.3 High-prio вытесняет low-prio

```bash
kubectl -n lab apply -f manifests/high-prio.yaml         # 300m, но места уже нет
sleep 8
kubectl -n lab get pod lab-high-pod                      # Running (через короткий Pending)
kubectl -n lab get pods -l app=lab-low-app               # ОДИН стал Pending (его вытеснили)

kubectl -n lab get events | grep -i preempt
# Normal  Preempted  pod/lab-low-app-...  Preempted by pod <high-uid> on node <NODE>
```

> ✅ **Прогнано на Kubespray:** high-prio был `Pending` ~секунду, затем scheduler
> ВЫСЕЛИЛ один lab-low под (событие `Preempted`) и поставил high-prio в `Running`;
> вытесненный low-prio ушёл в `Pending` (нода занята, nodeSelector держит его здесь).

```bash
# Уборка демо preemption + метки ноды (ОБЯЗАТЕЛЬНО):
kubectl -n lab delete deploy lab-low-app pod lab-high-pod --ignore-not-found
kubectl label node "$NODE" lab-prio-
kubectl delete priorityclass lab-low lab-high --ignore-not-found
```

**Контрольные вопросы:**
1. Что задаёт `PriorityClass` и как под к нему привязывается?
2. Что делает scheduler, если важному поду не хватает места (preemption)?
3. Чем priority (вытеснение) отличается от QoS (node-pressure eviction)?

---

## Часть 3: Enforcement лимитов — CPU throttle vs Memory OOM

### Теория для изучения перед частью

- **CPU — СЖИМАЕМЫЙ ресурс.** Превышение `limits.cpu` -> процесс ТОРМОЗЯТ
  (throttling, `nr_throttled` в cgroup), но НЕ убивают. Под жив, просто медленнее.
- **Memory — НЕсжимаемый.** Превышение `limits.memory` -> cgroup УБИВАЕТ контейнер
  (**OOMKilled**, exit code 137). Нельзя «чуть-чуть притормозить» память.
- **Overcommit:** сумма `limits` на ноде может превышать её ёмкость (лимиты — потолок,
  не резерв). Резервируются `requests`; по лимитам ноду можно переподписать.

---

**Цель:** увидеть OOMKilled при заниженном `limits.memory` и починку.

**Ресурсы:** `broken/scenario-01/oom-pod.yaml`, `solutions/01-oom/oom-pod.yaml`.

---

### 3.1 OOMKilled и решение

```bash
# Нагрузка ~100Mi при limits.memory=32Mi -> cgroup убивает контейнер
kubectl -n lab apply -f broken/scenario-01/oom-pod.yaml
sleep 12
kubectl -n lab get pod mem-hog
# mem-hog   0/1   OOMKilled   ...
kubectl -n lab get pod mem-hog -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
# OOMKilled                    <- exit 137, память превысила лимит

kubectl -n lab delete pod mem-hog
# Решение: поднять limits.memory до реального footprint (256Mi)
kubectl -n lab apply -f solutions/01-oom/oom-pod.yaml
sleep 8
kubectl -n lab get pod mem-hog   # Running/Completed — уложился в лимит
```

> ✅ **Прогнано на Kubespray:** при limit 32Mi контейнер OOMKilled (Failed); при
> limit 256Mi та же нагрузка работает. Урок: `limits.memory` должен покрывать
> реальный пик потребления; иначе — OOMKilled, и НИКАКОЙ throttling не спасёт
> (в отличие от CPU).

**Контрольные вопросы:**
1. Чем поведение при превышении `limits.cpu` отличается от `limits.memory`?
2. Что такое OOMKilled и какой exit code у контейнера?
3. Что такое overcommit и почему его допускают по limits, но не по requests?

---

## Часть 4: Troubleshooting

| Симптом | Причина | Диагностика / фикс |
|---------|---------|--------------------|
| Pod вечно `Pending` | нет ноды с таким свободным `requests` | `describe pod` -> `FailedScheduling: Insufficient cpu/memory`; снизить requests / добавить ёмкость |
| `OOMKilled` (exit 137) | превышен `limits.memory` | `lastState.terminated.reason`; поднять limit / чинить утечку |
| Под «тормозит» под нагрузкой | CPU-throttling на `limits.cpu` | поднять `limits.cpu`; throttling не убивает |
| Важный под не стартует, хотя нода занята «мелочью» | нет приоритета/preemption | дать `priorityClassName` повыше |
| Низкоприоритетный под внезапно `Pending` | его ВЫТЕСНИЛ (preempt) более важный | событие `Preempted`; это by design |

**Контрольные вопросы:**
1. `Pending` из-за ресурсов — где точная причина и как чинить?
2. Как отличить OOMKilled от обычного падения приложения?
3. Низкоприоритетный под ушёл в Pending без вашего участия — почему?

---

## Проверка модуля

```bash
kubectl -n lab apply -k manifests/      # QoS-поды + PriorityClass (детерминированная часть)
sleep 5
bash verify/verify.sh
# [OK] QoS classes assigned correctly (Guaranteed/Burstable/BestEffort)
# [OK] PriorityClass lab-low(100) + lab-high(1000) present
# [OK] module 12 verified
```

`verify.sh`: namespace `lab` → три qos-пода с правильным `qosClass` → `PriorityClass`
`lab-low`(100)/`lab-high`(1000) есть. Preemption и OOM — интерактивные части
(нужна разметка ноды / специально падают), в verify не входят.

---

## Финальная карта ресурсов модуля

| Ресурс | Часть | Что демонстрирует |
|--------|-------|-------------------|
| `qos-guaranteed`/`-burstable`/`-besteffort` | 1 | QoS-классы из requests/limits |
| `lab-low`/`lab-high` (PriorityClass) | 2 | уровни важности |
| `lab-low-app` (Deploy) + `lab-high-pod` | 2 | preemption (вытеснение) |
| `mem-hog` (broken→fix) | 3 | OOMKilled при заниженном limits.memory |

---

## Теоретические вопросы (итоговые)

1. requests vs limits: что для scheduler, что для cgroup?
2. Три QoS-класса: условия и порядок node-pressure eviction.
3. Что такое PriorityClass и preemption? Чем priority отличается от QoS?
4. CPU-throttling vs Memory-OOMKilled — почему память «убивают», а CPU «тормозят»?
5. Что такое overcommit и какие риски он несёт?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Создайте поды всех трёх QoS и подтвердите классы; объясните, кого выселят первым при нехватке памяти.
2. Разметьте ноду, заполните low-prio подами и вызовите preemption high-prio; найдите событие `Preempted`.
3. Воспроизведите OOMKilled (низкий `limits.memory`) и почините поднятием лимита; сравните с CPU-throttling.
4. Сделайте под `Pending` нехваткой CPU и прочитайте `FailedScheduling`.
5. Создайте свой `PriorityClass` и покажите, что под без приоритета вытесняется подом с ним.

---

## Шпаргалка

```bash
# === QoS ===
kubectl -n lab get pod <p> -o jsonpath='{.status.qosClass}'
# === Priority / preemption ===
kubectl get priorityclass
kubectl label node <worker> lab-prio=target --overwrite   # для демо preemption
kubectl -n lab get events | grep -i preempt
kubectl label node <worker> lab-prio-                      # снять метку
# === Limits / OOM ===
kubectl -n lab get pod <p> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'  # OOMKilled?
kubectl -n lab describe pod <p> | grep -A2 FailedScheduling                                          # почему Pending
kubectl describe node <node> | awk '/Allocated resources:/{f=1} f' | head -8                         # сколько уже зарезервировано

# === Уборка ===
kubectl -n lab delete -k manifests/
kubectl -n lab delete deploy lab-low-app pod lab-high-pod mem-hog --ignore-not-found
kubectl delete priorityclass lab-low lab-high --ignore-not-found
kubectl label node <worker> lab-prio- 2>/dev/null
```

---

## Уборка

```bash
kubectl -n lab delete -k manifests/
kubectl -n lab delete deploy lab-low-app --ignore-not-found
kubectl -n lab delete pod lab-high-pod mem-hog --ignore-not-found
kubectl delete priorityclass lab-low lab-high --ignore-not-found
# снять метку с ноды, если ставили в Части 2:
for n in $(kubectl get nodes -l lab-prio=target -o name); do kubectl label "$n" lab-prio-; done
```
