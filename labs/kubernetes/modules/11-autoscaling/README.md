# Лабораторная работа 11: Автомасштабирование (HPA, VPA, Cluster Autoscaler)

> ⏱ время ~25 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)

Цель: научиться автоматически менять число реплик под нагрузкой
(`HorizontalPodAutoscaler`), понимать разницу между горизонтальным,
вертикальным (VPA) и кластерным (Cluster Autoscaler) масштабированием, и читать
причину, по которой HPA «не работает». К концу модуля вы под нагрузкой видите
живой scale-up/down и чините классический инцидент `<unknown>` targets.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl -n lab delete deploy,svc,hpa,pod --all --ignore-not-found 2>/dev/null
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# HPA по CPU/RAM требует metrics-server. На GKE он есть; проверим:
kubectl top nodes >/dev/null 2>&1 && echo "metrics-server: OK" || echo "metrics-server НЕ готов — HPA по ресурсам не отработает"
```

> Для живого прогона нужны рабочие ноды. Наш Kubespray-кластер «паркуется»
> остановкой VM (`gcloud compute instances stop k8s-cp-1 k8s-w-1 k8s-w-2
> --zone us-central1-a`); вернуть — `... instances start ...`, после чего
> обновить внешние IP в kubeconfig/inventory (`cluster-kubespray/gen-inventory.sh`).

> **Портируемость (не только GKE).** HPA-ядро (объект HPA + scale-up по CPU)
> работает на ЛЮБОМ кластере, но требует metrics-server:
> - **GKE / k3s** — есть из коробки;
> - **kind / kubeadm** — поставить вручную: `kubectl apply -f
>   https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`
>   (для kind добавить контейнеру флаг `--kubelet-insecure-tls`);
> - **minikube** — `minikube addons enable metrics-server`.
>
> **Cluster Autoscaler** (Часть 3) — только там, где есть автоскейл нод-пула
> (GKE/EKS/AKS). На kind/одиночном kubeadm нод не добавит — поды останутся
> `Pending` (HPA при этом всё равно скейлит до предела ёмкости). **VPA** ставится
> отдельно на любом кластере.

---

## Стартовая проверка

```bash
# Версия HPA API: используем autoscaling/v2 (умеет несколько метрик и behavior)
kubectl api-resources | grep horizontalpodautoscaler
# horizontalpodautoscalers   hpa   autoscaling/v2   true   HorizontalPodAutoscaler
```

---

## Часть 1: HPA по CPU-утилизации

### Теория для изучения перед частью

- **HPA** периодически (по умолчанию ~15с) смотрит метрику подов и меняет
  `replicas`, стремясь к цели. Формула:
  `desired = ceil(currentReplicas × currentValue / targetValue)`.
- **CPU-утилизация считается от `requests.cpu`** (процент = usage / requests).
  Поэтому `requests.cpu` ОБЯЗАТЕЛЕН — без него HPA выдаёт `<unknown>`.
- Источник метрик — **metrics-server** (Resource-метрики CPU/RAM). Для custom/
  external метрик нужен адаптер (Prometheus Adapter).
- **`autoscaling/v2`** поддерживает несколько метрик, `Pods`/`Object`/`External`
  типы и `behavior` (политики/окна стабилизации scale-up/down).

**Формула на числах** (цель 50%, как в нашем `hpa.yaml`):

| currentReplicas | currentValue (CPU) | расчёт | desired |
|:---:|:---:|:---|:---:|
| 1 | 0% (нет нагрузки) | `ceil(1 × 0/50)` → 0, но не ниже `minReplicas` | **1** |
| 1 | 180% | `ceil(1 × 180/50)` = ceil(3.6) | **4** |
| 4 | 90% | `ceil(4 × 90/50)` = ceil(7.2) = 8, но `maxReplicas=5` | **5** (потолок) |
| 5 | 50% | `ceil(5 × 50/50)` = 5 — у цели, стабильно | **5** |

> **Зона нечувствительности (tolerance).** HPA НЕ реагирует, пока отношение
> `currentValue/targetValue` в пределах ±10% от 1.0 (флаг
> `--horizontal-pod-autoscaler-tolerance=0.1`). Т.е. при цели 50% реакции не будет
> на 45–55% — это гасит «дребезг» вокруг цели.

---

**Цель:** повесить HPA на Deployment и убедиться, что метрика читается.

**Ресурсы:** `manifests/{deploy,svc,hpa}.yaml` (`hpa-demo` + HPA 1→5 @ 50% CPU).

---

### 1.1 Deployment + HPA

```bash
kubectl -n lab apply -f manifests/deploy.yaml -f manifests/svc.yaml -f manifests/hpa.yaml
kubectl -n lab rollout status deploy/hpa-demo --timeout=120s

# Через ~15-60с метрика появится (TARGETS перестанет быть <unknown>)
kubectl -n lab get hpa hpa-demo
# NAME       REFERENCE             TARGETS       MINPODS  MAXPODS  REPLICAS
# hpa-demo   Deployment/hpa-demo   cpu: 0%/50%   1        5        1
#                                       ^ usage/target; 0% т.к. нагрузки нет
```

**Контрольные вопросы:**
1. По какой формуле HPA вычисляет желаемое число реплик?
2. Почему для HPA по CPU обязателен `requests.cpu`?
3. Что даёт `autoscaling/v2` по сравнению с `v1`?

---

## Часть 2: Нагрузка и масштабирование

### Теория для изучения перед частью

- При росте средней утилизации выше цели HPA добавляет реплики (до `maxReplicas`),
  при падении — убирает (до `minReplicas`).
- **Стабилизация:** чтобы не «дёргать» нагрузку, scale-down притормаживается окном
  (`behavior.scaleDown.stabilizationWindowSeconds`, по умолчанию 300с). Scale-up
  быстрее scale-down — это сознательный выбор.

**Асимметрия scale-up vs scale-down на таймлайне:**

```
CPU% │      ┌──────────────┐ нагрузка
 180 │      │              │
  50 │──────┘              └────────────── цель
     │
repl │      ▲ scale-UP за ~15-60с          ▼ scale-DOWN только ПОСЛЕ окна
   5 │      ┌───────────────────────────┐  стабилизации (default 300с)
   1 │──────┘                           └──────────── вниз медленно
     └──────┬──────────────────┬────────┬───────────────────────> t
          нагрузка↑         нагрузка↓   +окно 300с: HPA берёт МАКСИМУМ
                                        рекомендаций за окно -> только потом режет
```

> **Почему асимметрия.** Вверх — быстро, чтобы не уронить сервис под пиком. Вниз —
> с задержкой: кратковременный провал нагрузки не должен убить реплики, которые
> тут же снова понадобятся (flapping). В окне scale-down HPA берёт НАИБОЛЬШУЮ из
> рекомендаций — поэтому единичный провал до 0% не схлопнет реплики мгновенно.

---

**Цель:** увидеть живой scale-up под нагрузкой и scale-down после.

---

### 2.1 Scale-up под нагрузкой

```bash
# Генератор: в цикле бьёт по сервису, нагружая CPU php-apache
kubectl -n lab run load --image=busybox:1.36 --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://hpa-demo; done'

# Наблюдаем рост утилизации и реплик (Ctrl+C для выхода)
kubectl -n lab get hpa hpa-demo -w
# TARGETS  cpu: 0%/50%   REPLICAS 1
# TARGETS  cpu: 180%/50% REPLICAS 1   <- нагрузка пошла
# TARGETS  cpu: 90%/50%  REPLICAS 4   <- HPA добавил реплики, утилизация падает
# TARGETS  cpu: 50%/50%  REPLICAS 5   <- стабилизировалось у цели/максимума

kubectl -n lab describe hpa hpa-demo | grep -A3 Events
# SuccessfulRescale  New size: 4; reason: cpu resource utilization above target
```

### 2.2 Scale-down после снятия нагрузки

```bash
kubectl -n lab delete pod load
# Через стабилизационное окно (здесь 120с) реплики вернутся к minReplicas:
kubectl -n lab get hpa hpa-demo -w
# TARGETS cpu: 0%/50%  REPLICAS 5 -> ... -> 1
```

**Контрольные вопросы:**
1. Что произойдёт с репликами при превышении и при падении утилизации?
2. Зачем scale-down притормаживают окном стабилизации, а scale-up — нет?
3. Что ограничивает рост реплик сверху?

---

## Часть 3: VPA и Cluster Autoscaler (обзор)

### Теория для изучения перед частью

**Три уровня автоскейла — что масштабируют и чем триггерятся:**

| | **HPA** | **VPA** | **Cluster Autoscaler** |
|---|---|---|---|
| Объект | `replicas` (Deployment/STS) | `requests`/`limits` пода | число **НОД** в пуле |
| Направление | горизонтально (больше подов) | вертикально (жирнее под) | инфраструктура |
| Триггер | метрика выше/ниже цели | факт. потребление vs requests | `Pending`-поды / пустые ноды |
| Реакция | +/− поды (живо) | пересоздать под с новыми requests | +/− ноды (минуты) |
| Где работает | любой кластер + metrics-server | ставится отдельно (VPA CRD) | managed/автоскейл-пул (GKE/EKS/AKS) |
| Сочетаемость | — | ⚠️ HPA+VPA по ОДНОЙ метрике (CPU) конфликтуют | дополняет HPA |

- ⚠️ **HPA и VPA нельзя по одной метрике:** HPA добавляет поды (снижая среднюю
  утилизацию), VPA по той же утилизации раздувает requests — они «воюют». VPA
  допустим вместе с HPA только по РАЗНЫМ метрикам (напр. VPA по RAM, HPA по CPU).
- **Цепочка:** рост нагрузки → HPA добавляет поды → не хватило нод → поды `Pending`
  → CA добавляет ноды → поды стартуют. (HPA масштабирует «спрос», CA — «ёмкость».)

**Архитектура VPA — три компонента.** VPA это не один процесс, а три (ставятся
отдельным деплоем, не входят в k8s):

```
   Recommender ── читает usage (metrics-server/Prometheus) и историю →
                  считает рекомендацию requests/limits, пишет в VPA.status
        │
   Updater ────── видит под, чьи requests далеки от рекомендации →
                  ВЫСЕЛЯЕТ его (под пересоздаётся)
        │
   Admission Controller ── на admission нового пода ПОДМЕНЯЕТ requests/limits
                           рекомендованными (mutating-webhook)
```

- **Почему выселяет:** requests пода **иммутабельны** у запущенного пода (до
  in-place resize, который ещё не повсеместен) — поэтому изменить их можно только
  пересозданием. Отсюда главный минус VPA: рестарт пода (см. PDB, модуль 13).

**Четыре режима VPA (`updatePolicy.updateMode`):**

| Режим | Что делает | Когда |
|---|---|---|
| `Off` | только считает рекомендацию (status), НЕ применяет | разведка — узнать «правильные» requests, выставить руками |
| `Initial` | задаёт requests только при СОЗДАНИИ пода | без рестартов работающих |
| `Recreate` | выселяет и пересоздаёт под при сильном расхождении | можно простой |
| `Auto` | сейчас = `Recreate` (в будущем — in-place resize) | полный автопилот |

> Практика: начинают с `Off`, смотрят рекомендации `kubectl describe vpa`, потом
> либо применяют руками, либо включают `Initial`/`Recreate`. `Auto` + HPA по одной
> метрике — не делать (см. конфликт выше).

---

### 3.1 Связь HPA → Cluster Autoscaler

```bash
# Если HPA упрётся в нехватку ресурсов нод, новые поды зависнут в Pending:
kubectl -n lab get pods -l app=hpa-demo --field-selector=status.phase=Pending
# При включённом CA на ноды появится событие:
kubectl get events -A | grep -iE "TriggeredScaleUp|NotTriggerScaleUp" | tail -3

# Включить автоскейл нод на GKE (пример):
# gcloud container clusters update lab-cluster --enable-autoscaling \
#   --node-pool lab-cluster-pool --min-nodes 1 --max-nodes 4 --zone us-central1-a
```

**Контрольные вопросы:**
1. Чем HPA отличается от VPA и почему их нельзя комбинировать по одной метрике?
2. Что является триггером для Cluster Autoscaler?
3. Опишите цепочку «нагрузка → HPA → CA».

---

## Часть 4: Troubleshooting

### Теория: дерево диагностики HPA `<unknown>`

`<unknown>` в TARGETS значит «HPA не смог получить/посчитать метрику». Причин
несколько — отсекать по порядку:

```
HPA TARGETS = <unknown>/50% ?
   │
   ├─ kubectl top pods -n lab
   │     ├─ "Metrics API not available" ──> НЕТ metrics-server          → Инцидент 2
   │     └─ числа есть ──┐
   │                     ▼
   ├─ у пода задан requests.cpu?
   │     kubectl -n lab get deploy hpa-demo \
   │       -o jsonpath='{.spec.template.spec.containers[0].resources.requests}'
   │     ├─ пусто ──> НЕТ requests.cpu (процент не от чего считать) → Инцидент 1
   │     └─ есть ──┐
   │               ▼
   ├─ поды Running и Ready?  (метрики берутся только с Ready-подов)
   │     ├─ нет ──> чинить под (CrashLoop/Pending/ErrImagePull) — см. модуль 02/08
   │     └─ да ──┐
   │             ▼
   └─ под создан только что? ──> подожди 15-60с (первый scrape metrics-server)
```

| Симптом | Команда | Что искать |
|---------|---------|------------|
| `<unknown>` в TARGETS | `kubectl -n lab describe hpa hpa-demo` | `FailedGetResourceMetric` / `unable to compute` |
| нет источника метрик | `kubectl top pods -n lab` | `Metrics API not available` |
| нет requests | `kubectl -n lab get deploy hpa-demo -o jsonpath='{..resources.requests}'` | пустой вывод |
| не масштабирует | `kubectl -n lab describe hpa hpa-demo` → Events | `SuccessfulRescale` vs `FailedGetScale` |
| реплики выросли, но `Pending` | `kubectl -n lab describe pod -l app=hpa-demo` | `FailedScheduling: Insufficient cpu` |

---

### Инцидент 1: HPA показывает `<unknown>/50%` — нет `requests.cpu`

Оформлен в `broken/scenario-01/`.

**Воспроизведение:**

```bash
kubectl -n lab apply -f broken/scenario-01/deploy.yaml   # Deployment без requests
kubectl -n lab apply -f manifests/hpa.yaml
sleep 30
```

**Диагностика:**

```bash
kubectl -n lab get hpa hpa-demo
# TARGETS: <unknown>/50%        <- HPA не может посчитать процент

kubectl -n lab describe hpa hpa-demo | grep -A2 -iE "unable|FailedGetResourceMetric|missing request"
# the HPA was unable to compute the replica count: failed to get cpu utilization:
#   missing request for cpu in container php-apache
```

**Решение:**

```bash
kubectl -n lab apply -f solutions/01-no-requests/deploy.yaml   # добавлен requests.cpu
kubectl -n lab get hpa hpa-demo                                 # TARGETS -> 0%/50%
```

**Профилактика:** для любого workload под HPA задавать `requests.cpu`/`memory`;
проверять `kubectl get hpa` после деплоя на `<unknown>`.

### Инцидент 2: HPA не масштабирует — нет metrics-server

```bash
# Симптом: тот же <unknown>, но requests заданы. Причина — нет источника метрик.
kubectl top pods -n lab
# error: Metrics API not available   <- metrics-server не установлен
# Лечение: установить metrics-server (на kind), на GKE он есть из коробки.
```

### Инцидент 3: scale-up есть, но поды `Pending`

```bash
# HPA увеличил replicas, но нодам не хватает ресурсов:
kubectl -n lab describe pod -l app=hpa-demo | grep -A1 FailedScheduling
# 0/2 nodes are available: Insufficient cpu.
# Лечение: включить Cluster Autoscaler (добавит ноды) или поднять ёмкость нод.
```

**Контрольные вопросы:**
1. Две причины `<unknown>` в TARGETS у HPA?
2. Как отличить «нет requests» от «нет metrics-server»?
3. Почему HPA может «упереться» даже при рабочих метриках?

---

## Проверка модуля

```bash
kubectl -n lab apply -f manifests/deploy.yaml -f manifests/svc.yaml -f manifests/hpa.yaml
kubectl -n lab rollout status deploy/hpa-demo --timeout=120s
sleep 30   # дать HPA снять первую метрику

bash verify/verify.sh
# [OK] hpa-demo metric available (current CPU utilization = 0%)
# [OK] module 11 verified
```

`verify.sh`: namespace `lab` → `Deployment/hpa-demo` готов → есть `HPA/hpa-demo` →
HPA видит метрику (не `<unknown>`). Если метрика ещё прогревается — мягкий
`[WARN]`, не провал. Две `[OK]`-строки при успехе.

---

## Финальная карта ресурсов модуля

| Ресурс | Что демонстрирует |
|--------|-------------------|
| `hpa-demo` (Deployment) | CPU-bound нагрузка с `requests.cpu` |
| `hpa-demo` (Service) | точка входа для генератора нагрузки |
| `hpa-demo` (HPA v2) | автоскейл 1→5 по 50% CPU + стабилизация |
| `load` (Pod) | генератор нагрузки для scale-up |

---

## Теоретические вопросы (итоговые)

1. Выведите формулу желаемых реплик HPA и объясните роль `requests`.
2. Чем HPA / VPA / Cluster Autoscaler отличаются по объекту масштабирования?
3. Почему scale-down медленнее scale-up и как это настраивается?
4. Назовите две причины `<unknown>` в TARGETS и как их различить.
5. Опишите цепочку автоскейла от роста нагрузки до добавления нод.

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Под нагрузкой (генератор) поймайте scale-up `1→5`; после снятия — наблюдайте окно стабилизации scale-down.
2. Воспроизведите `<unknown>` двумя способами (нет `requests.cpu` / нет metrics-server) и различите их по диагностике.
3. Посчитайте по формуле HPA желаемые реплики для 3 значений утилизации и сверьте с фактом.
4. Поменяйте `averageUtilization` цель и проследите, как меняется число реплик при той же нагрузке.
5. Уроните под до `Pending` (большой `requests`) под HPA и объясните, чем тут поможет Cluster Autoscaler.

---

## Шпаргалка

```bash
# === HPA ===
kubectl -n lab get hpa hpa-demo
kubectl -n lab describe hpa hpa-demo                 # Events: SuccessfulRescale / Failed...
kubectl -n lab get hpa hpa-demo -o jsonpath='{.status.currentMetrics}'
kubectl -n lab autoscale deploy hpa-demo --cpu-percent=50 --min=1 --max=5   # императивно

# === Нагрузка / наблюдение ===
kubectl -n lab run load --image=busybox:1.36 --restart=Never -- sh -c 'while true; do wget -q -O- http://hpa-demo; done'
kubectl -n lab get hpa hpa-demo -w
kubectl top pods -n lab

# === Cluster Autoscaler (GKE) ===
kubectl get events -A | grep -iE "TriggeredScaleUp|NotTriggerScaleUp"

# === Уборка ===
kubectl -n lab delete pod load --ignore-not-found
kubectl -n lab delete -k manifests/
```

---

## Уборка

```bash
kubectl -n lab delete pod load --ignore-not-found
kubectl -n lab delete -k manifests/
```
