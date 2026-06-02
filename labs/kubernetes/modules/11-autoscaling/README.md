# Лабораторная работа 11: Автомасштабирование (HPA, VPA, Cluster Autoscaler)

Цель: научиться автоматически менять число реплик под нагрузкой
(`HorizontalPodAutoscaler`), понимать разницу между горизонтальным,
вертикальным (VPA) и кластерным (Cluster Autoscaler) масштабированием, и читать
причину, по которой HPA «не работает». К концу модуля вы под нагрузкой видите
живой scale-up/down и чините классический инцидент `<unknown>` targets.

---

## Предварительные требования

```bash
kubectl -n lab delete deploy,svc,hpa,pod --all --ignore-not-found 2>/dev/null
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# HPA по CPU/RAM требует metrics-server. На GKE он есть; проверим:
kubectl top nodes >/dev/null 2>&1 && echo "metrics-server: OK" || echo "metrics-server НЕ готов — HPA по ресурсам не отработает"
```

> Для живого прогона нужны рабочие ноды. Если кластер «припаркован» (0 нод),
> верните их: в `cluster-gke/` — `terraform apply` (node_count=2).

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

- **HPA** — горизонтально (больше ПОДОВ). **VPA** — вертикально (меняет
  `requests`/`limits` подов; обычно пересоздаёт под). HPA и VPA по ОДНОЙ метрике
  (CPU) одновременно конфликтуют — не сочетать.
- **Cluster Autoscaler (CA)** масштабирует НОДЫ: видит `Pending`-поды (которым не
  хватило места) и добавляет ноды в автоскейл-пул; пустые ноды убирает. На
  managed (GKE/EKS) включается на node pool.
- Цепочка: рост нагрузки → HPA добавляет поды → не хватило нод → поды `Pending`
  → CA добавляет ноды → поды стартуют.

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
