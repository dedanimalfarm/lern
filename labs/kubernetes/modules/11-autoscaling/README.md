# Лабораторная работа 11: Автомасштабирование (HPA, VPA, Cluster Autoscaler)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Часть 1: Введение в автомасштабирование и HPA по CPU](#часть-1-введение-в-автомасштабирование-и-hpa-по-cpu)
  - [1.1 Зачем нужно автомасштабирование (Теория)](#11-зачем-нужно-автомасштабирование-теория)
  - [1.2 Архитектура и математика HPA](#12-архитектура-и-математика-hpa)
  - [1.3 Практика: Deployment + HPA](#13-практика-deployment--hpa)
- [Часть 2: Нагрузочное тестирование и тонкая настройка (Behavior)](#часть-2-нагрузочное-тестирование-и-тонкая-настройка-behavior)
  - [2.1 Асимметрия и Policies (Теория)](#21-асимметрия-и-policies-теория)
  - [2.2 Практика: Scale-up под нагрузкой](#22-практика-scale-up-под-нагрузкой)
  - [2.3 Практика: Scale-down после снятия нагрузки](#23-практика-scale-down-после-снятия-нагрузки)
- [Часть 3: VPA (Vertical Pod Autoscaler)](#часть-3-vpa-vertical-pod-autoscaler)
  - [3.1 Архитектура VPA (Теория)](#31-архитектура-vpa-теория)
  - [3.2 Почему HPA и VPA конфликтуют?](#32-почему-hpa-и-vpa-конфликтуют)
  - [3.3 Практика: Наблюдение за рекомендациями VPA](#33-практика-наблюдение-за-рекомендациями-vpa)
- [Часть 4: Cluster Autoscaler (CA)](#часть-4-cluster-autoscaler-ca)
  - [4.1 Как работает CA (Теория)](#41-как-работает-ca-теория)
  - [4.2 Цепочка HPA → CA](#42-цепочка-hpa--ca)
- [Часть 5: Продвинутое масштабирование (KEDA, Karpenter, DRA)](#часть-5-продвинутое-масштабирование-keda-karpenter-dra)
  - [5.1 KEDA (Kubernetes Event-driven Autoscaling)](#51-keda-kubernetes-event-driven-autoscaling)
  - [5.2 Karpenter (Оптимизированный Node Provisioning)](#52-karpenter-оптимизированный-node-provisioning)
  - [5.3 DRA (Dynamic Resource Allocation)](#53-dra-dynamic-resource-allocation)
- [Часть 6: Troubleshooting (Расширенный)](#часть-6-troubleshooting-расширенный)
  - [Дерево диагностики HPA `<unknown>`](#дерево-диагностики-hpa-unknown)
  - [Инцидент 1: HPA показывает `<unknown>/50%` — нет `requests.cpu`](#инцидент-1-hpa-показывает-unknown50--нет-requestscpu)
  - [Инцидент 2: HPA не масштабирует — нет metrics-server](#инцидент-2-hpa-не-масштабирует--нет-metrics-server)
  - [Инцидент 3: Scale-up есть, но поды `Pending`](#инцидент-3-scale-up-есть-но-поды-pending)
  - [Инцидент 4: Flapping (дребезг) реплик](#инцидент-4-flapping-дребезг-реплик)
  - [Инцидент 5: Ошибка чтения Custom Metrics](#инцидент-5-ошибка-чтения-custom-metrics)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
<!-- /TOC -->


> ⏱ время ~45 мин · сложность 4/5 · пререквизиты: Трек 1 (Core)

Цель: научиться автоматически менять число реплик под нагрузкой (`HorizontalPodAutoscaler`), глубоко понимать разницу между горизонтальным (HPA), вертикальным (VPA) и кластерным (Cluster Autoscaler) масштабированием. Вы научитесь читать причину, по которой HPA «не работает», настраивать поведение (behavior) автомасштабирования для предотвращения flapping-а, а также разберетесь с архитектурой масштабирования инфраструктуры (Karpenter) и событийного масштабирования (KEDA).

К концу модуля вы под нагрузкой увидите живой scale-up/down, почините классический инцидент `<unknown>` targets и сможете уверенно управлять ресурсами кластера.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf

# Создаем namespace для изоляции ресурсов лаборатории
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# Очищаем namespace от предыдущих запусков, чтобы начать с чистого листа
kubectl -n lab delete deploy,svc,hpa,pod,vpa --all --ignore-not-found 2>/dev/null

# HPA по CPU/RAM требует metrics-server. 
# На многих managed кластерах (GKE, EKS) он есть из коробки. Проверим:
kubectl top nodes >/dev/null 2>&1 && echo "metrics-server: OK" || echo "metrics-server НЕ готов — HPA по ресурсам не отработает"
```

> **Важно: Инфраструктура для живого прогона.**
> Для полноценного выполнения практик нужны рабочие воркер-ноды. Наш учебный Kubespray-кластер может «парковаться» остановкой VM в облаке (`gcloud compute instances stop k8s-cp-1 k8s-w-1 k8s-w-2 --zone us-central1-a`). Чтобы его разбудить — выполните команду `start`, после чего необходимо обновить внешние IP-адреса в kubeconfig и inventory (используйте скрипт `cluster-kubespray/gen-inventory.sh`).

> **Портируемость (Где работают эти технологии).** 
> HPA-ядро (объект HPA + scale-up по базовым метрикам CPU/RAM) является встроенным контроллером Kubernetes (входит в `kube-controller-manager`) и работает на ЛЮБОМ кластере, но строго требует установленного поставщика метрик `metrics-server`:
> - **GKE / AKS / DOKS / k3s** — предустановлен из коробки;
> - **EKS / kind / kubeadm** — требует ручной установки: `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` (для `kind` не забудьте добавить флаг `--kubelet-insecure-tls` в аргументы контейнера `metrics-server`);
> - **minikube** — активируется аддоном: `minikube addons enable metrics-server`.
>
> **Cluster Autoscaler** (Часть 4) и **Karpenter** — работают только там, где есть API управления виртуальными машинами (AWS, GCP, Azure, OpenStack). На локальном `kind` или статичном `kubeadm` "железе" ноды сами не появятся — поды просто останутся висеть в статусе `Pending` (хотя HPA честно увеличит параметр `replicas` до предела). 
> **VPA** ставится отдельно на любом кластере как набор Custom Resource Definitions и операторов.

---

## Стартовая проверка

Давайте убедимся, что кластер поддерживает нужную нам версию API для HPA. Начиная с Kubernetes 1.23, API `autoscaling/v2` стало стабильным и заменило старые `v2beta1/v2beta2`.

```bash
# Проверяем версию HPA API: используем autoscaling/v2 (поддерживает behavior и custom metrics)
kubectl api-resources | grep horizontalpodautoscaler
# Вывод должен быть примерно таким:
# horizontalpodautoscalers   hpa   autoscaling/v2   true   HorizontalPodAutoscaler
```

---

## Часть 1: Введение в автомасштабирование и HPA по CPU

### 1.1 Зачем нужно автомасштабирование (Теория)

В современном мире нагрузка на веб-приложения редко бывает равномерной. Обычно наблюдаются суточные паттерны (днем пользователей много, ночью мало), всплески трафика из-за маркетинговых кампаний (Black Friday) или непредвиденные DDoS-атаки.

Держать кластер всегда масштабированным под пиковую нагрузку — **очень дорого** (вы платите за простаивающие серверы). Масштабировать под среднюю нагрузку — **рискованно** (приложение "ляжет" во время пика). 

**Автомасштабирование (Autoscaling)** решает эту дилемму, динамически подстраивая количество ресурсов под текущий спрос. Это достигается комбинацией процессов:
1. **Application Scaling (HPA/VPA):** Увеличиваем/уменьшаем размер самого приложения внутри кластера.
2. **Infrastructure Scaling (CA/Karpenter):** Увеличиваем/уменьшаем количество физических или виртуальных серверов (нод) под нужды кластера.

### 1.2 Архитектура и математика HPA

**Horizontal Pod Autoscaler (HPA)** реализован как контроллер внутри `kube-controller-manager`. Он периодически (по умолчанию раз в 15 секунд, настраивается флагом `--horizontal-pod-autoscaler-sync-period`) опрашивает Resource Metrics API или Custom Metrics API, забирая метрики целевых подов, и рассчитывает необходимое число реплик.

#### Архитектурная схема HPA:

```text
                                +---------------------------+
                                | kube-controller-manager   |
                                |   [ HPA Controller ]      |
                                +---------------------------+
                                         |         ^
                       (1) Get Metrics   |         | (2) Usage Data
                                         v         |
+-------------------+            +---------------------------+
| Target Workload   | <--------- |      Metrics API          |
| (Deployment/STS)  | (4) Scale  | (metrics-server / KEDA)   |
+-------------------+            +---------------------------+
       |                                     ^
       v                                     | (3) Scrape (cAdvisor)
+-------------------+                        |
| Pod | Pod | Pod   | -----------------------+
+-------------------+
```

#### Математика HPA:
- **HPA-формула** для вычисления желаемого числа реплик предельно проста:
  `desiredReplicas = ceil[currentReplicas * (currentMetricValue / desiredMetricValue)]`
- **CPU-утилизация считается от `requests.cpu`** (процент = usage / requests). Если у пода нет `requests.cpu`, HPA не может вычислить процент, выдаст ошибку `<unknown>` и **не будет** масштабировать приложение.

**Пример вычисления на числах** (Цель: 50% CPU, как в нашем `hpa.yaml`):

| Текущие реплики | Текущая нагрузка (CPU) | Расчёт по формуле | Желаемые реплики |
|:---:|:---:|:---|:---:|
| 1 | 0% (нет нагрузки) | `ceil(1 × 0/50)` → 0, но не ниже `minReplicas` | **1** |
| 1 | 180% | `ceil(1 × 180/50)` = ceil(3.6) | **4** |
| 4 | 90% | `ceil(4 × 90/50)` = ceil(7.2) = 8, но `maxReplicas=5` | **5** (уперлись в потолок) |
| 5 | 50% | `ceil(5 × 50/50)` = 5 — у цели, стабильно | **5** |

> **Зона нечувствительности (Tolerance).** 
> HPA НЕ реагирует, пока отношение `currentValue/desiredValue` находится в пределах ±10% от 1.0 (задается флагом `--horizontal-pod-autoscaler-tolerance=0.1`). То есть, при цели 50%, HPA будет игнорировать флуктуации нагрузки от 45% до 55%. Это сделано специально, чтобы гасить «дребезг» (thrashing) и не пересоздавать поды из-за минимальных скачков метрик.

### 1.3 Практика: Deployment + HPA

Создадим простое приложение, которое сильно нагружает процессор при HTTP-запросах (образ `k8s.gcr.io/hpa-example` - это PHP скрипт, считающий квадратные корни в цикле).

**Цель:** повесить HPA на Deployment и убедиться, что метрика читается.

```bash
# Применяем ресурсы: Deployment, Service и HPA
kubectl -n lab apply -f manifests/deploy.yaml -f manifests/svc.yaml -f manifests/hpa.yaml

# Дожидаемся готовности Deployment
kubectl -n lab rollout status deploy/hpa-demo --timeout=120s

# Через ~15-60с метрика появится. Kubelet собирает метрики (cAdvisor), 
# metrics-server их забирает, а HPA Controller опрашивает metrics-server.
# Из-за этой цепочки первая метрика появляется с задержкой!
kubectl -n lab get hpa hpa-demo
# Ожидаемый вывод (пока нагрузки нет):
# NAME       REFERENCE             TARGETS       MINPODS  MAXPODS  REPLICAS
# hpa-demo   Deployment/hpa-demo   0%/50%        1        5        1
```

Обратите внимание, что `TARGETS` показывает `0%/50%`. Это значит:
- Текущая утилизация `0%` (от `requests.cpu`)
- Желаемая цель `50%`

---

## Часть 2: Нагрузочное тестирование и тонкая настройка (Behavior)

### 2.1 Асимметрия и Policies (Теория)

HPA спроектирован так, чтобы защищать приложение:
- **Scale-up (рост)** происходит максимально быстро. Как только нагрузка возрастает, HPA моментально добавляет поды, чтобы сервис не деградировал.
- **Scale-down (уменьшение)** происходит медленно и с задержкой. Если нагрузка упала, HPA ждет так называемое **окно стабилизации** (по умолчанию 300 секунд / 5 минут). 

**Зачем нужно окно стабилизации (Stabilization Window)?**
Временный провал нагрузки (например, на 10 секунд из-за сетевого скачка) не должен убивать реплики, которые тут же снова понадобятся. В окне scale-down HPA запоминает все рекомендации за последние 5 минут и берет **НАИБОЛЬШУЮ** из них. Таким образом, scale-down начнется только если нагрузка стабильно низкая в течение всех 5 минут.

**Визуализация асимметрии на таймлайне:**
```text
CPU% │      ┌──────────────┐ нагрузка (резкий скачок и падение)
 180 │      │              │
  50 │──────┘              └────────────── цель
     │
repl │      ▲ scale-UP за ~15-60с          ▼ scale-DOWN только ПОСЛЕ окна
   5 │      ┌───────────────────────────┐  стабилизации (default 300с)
   1 │──────┘                           └──────────── вниз медленно
     └──────┬──────────────────┬────────┬───────────────────────> t
          нагрузка↑         нагрузка↓   +окно 300с ожидания
```

В API `autoscaling/v2` появилось поле `behavior`, позволяющее переопределить эту логику (например, сделать scale-down быстрым, или ограничить scale-up, чтобы не убить базу данных шквалом новых коннектов).

Пример `behavior` (можно изучить в документации k8s):
```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 120 # Ждем 2 минуты вместо 5
    policies:
    - type: Pods
      value: 1
      periodSeconds: 15 # Убиваем не более 1 пода каждые 15 сек
  scaleUp:
    stabilizationWindowSeconds: 0 # Мгновенная реакция
```

### 2.2 Практика: Scale-up под нагрузкой

Запустим отдельный под, который будет бесконечно дергать наш сервис `hpa-demo` по HTTP, генерируя высокую CPU нагрузку.

```bash
# Генератор нагрузки (бесконечный wget)
kubectl -n lab run load --image=busybox:1.36 --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://hpa-demo; done'

# Наблюдаем рост утилизации и реплик (Используйте -w для watch-режима; Ctrl+C для выхода)
kubectl -n lab get hpa hpa-demo -w
# Примерный ход событий:
# TARGETS  cpu: 0%/50%   REPLICAS 1
# TARGETS  cpu: 180%/50% REPLICAS 1   <- Нагрузка пошла. Формула: 1 * (180/50) = 3.6 -> 4 пода
# TARGETS  cpu: 90%/50%  REPLICAS 4   <- HPA добавил реплики. Утилизация размазывается
# TARGETS  cpu: 50%/50%  REPLICAS 5   <- Стабилизировалось у цели (максимум)

# Посмотрим историю решений HPA через Events:
kubectl -n lab describe hpa hpa-demo | grep -A5 Events
# Events:
#   Type    Reason             Age   From                       Message
#   ----    ------             ----  ----                       -------
#   Normal  SuccessfulRescale  1m    horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
#   Normal  SuccessfulRescale  30s   horizontal-pod-autoscaler  New size: 5; reason: cpu resource utilization (percentage of request) above target
```

### 2.3 Практика: Scale-down после снятия нагрузки

Теперь остановим генератор нагрузки и понаблюдаем за поведением кластера.

```bash
# Удаляем под-генератор
kubectl -n lab delete pod load

# Наблюдаем за HPA. Реплики НЕ исчезнут мгновенно из-за Stabilization Window!
# В нашем кастомном манифесте hpa.yaml мы переопределили окно scale-down на 60 секунд 
# для целей обучения (чтобы не ждать 5 минут).
kubectl -n lab get hpa hpa-demo -w
# Ожидаемый вывод:
# TARGETS cpu: 0%/50%  REPLICAS 5  <- Нагрузка 0, но реплик 5 (ждем окно)
# ... проходит ~60 секунд ...
# TARGETS cpu: 0%/50%  REPLICAS 1  <- HPA плавно спустил реплики до минимума
```

**Контрольные вопросы (Часть 1-2):**
1. По какой формуле HPA вычисляет желаемое число реплик?
2. Почему для HPA по CPU обязателен параметр `requests.cpu` в контейнере?
3. Что такое зона нечувствительности (Tolerance) и зачем она нужна?
4. Зачем scale-down притормаживают окном стабилизации по умолчанию на 5 минут?
5. Что ограничивает рост количества реплик сверху?

---

## Часть 3: VPA (Vertical Pod Autoscaler)

### 3.1 Архитектура VPA (Теория)

Если HPA увеличивает **количество** подов, то VPA (Vertical Pod Autoscaler) увеличивает/уменьшает **размер** самих подов (меняет их `requests` и `limits`). VPA идеально подходит для stateful-приложений, баз данных или монолитов, которые не умеют масштабироваться горизонтально (добавлять реплики).

**Архитектура VPA состоит из трех отдельных компонентов:**

```text
    [ Prometheus / Metrics Server ]
                |
                v (Usage data)
       +-----------------+        (writes recommendations)
       | VPA Recommender | ----------------------------------+
       +-----------------+                                   |
                                                             v
+-------------+      (evicts pods with wrong requests)   [ VPA Object Status ]
| VPA Updater | <------------------------------------------+ |
+-------------+                                              |
       |                                                     |
       v (Eviction API)                                      |
+-------------------+      (intercepts new pods)             |
| Pod (old size)    |      +------------------------+        |
| -> terminates     |      | VPA Admission Control  | <------+
+-------------------+      | (Mutating Webhook)     |
                           +------------------------+
                                      | (injects new requests)
                                      v
                           +-------------------+
                           | Pod (new size)    |
                           +-------------------+
```

- **Recommender:** Наблюдает за потреблением CPU/RAM подов и рассчитывает идеальные `requests/limits`, записывая их в статус объекта VPA.
- **Updater:** Периодически сканирует запущенные поды. Если текущие `requests` пода сильно отличаются от рекомендаций, Updater **убивает (evict)** под.
- **Admission Controller:** Когда контроллер (Deployment) пересоздает убитый под, VPA Webhook перехватывает запрос и "на лету" подменяет `requests/limits` в манифесте на новые, рекомендованные значения.

> **Почему VPA выселяет (рестартует) поды?**
> В Kubernetes (до появления стабильного In-Place Pod Resizing) ресурсы `requests/limits` были **иммутабельными** (неизменяемыми) у работающего пода. Изменить их можно было только пересоздав контейнер. Отсюда главный минус VPA — кратковременный даунтайм приложения.

**Четыре режима работы VPA (`updatePolicy.updateMode`):**

| Режим | Описание | Применение на практике |
|---|---|---|
| `Off` | Только рассчитывает рекомендации, но НЕ применяет их к подам. | Идеально для "разведки": узнать, сколько ресурсов реально нужно приложению, чтобы потом жестко зафиксировать их в Helm-чарте. |
| `Initial` | Применяет рекомендации только в момент старта пода. | Избегаем случайных рестартов во время работы. |
| `Recreate` | Убивает и пересоздает под при сильном расхождении ресурсов. | Полный автопилот, но требует PDB (PodDisruptionBudget) для защиты от простоя. |
| `Auto` | Сейчас работает как `Recreate` (в будущем перейдет на in-place resize). | Автопилот по умолчанию. |

### 3.2 Почему HPA и VPA конфликтуют?

⚠️ **Грубая ошибка: Использовать HPA и VPA одновременно на одной и той же метрике (например, CPU).**

Представьте цикл:
1. Приложение получает трафик, CPU прыгает до 90%.
2. HPA реагирует: добавляет реплики с 2 до 5. 
3. Нагрузка размазывается по 5 подам, средний CPU падает до 20%.
4. VPA Recommender видит средний CPU 20% и решает: "Ого, поды огромные, надо урезать `requests`". VPA убивает поды и пересоздает их с маленьким `requests`.
5. Поды становятся крошечными. Любой мелкий запрос заставляет их CPU снова подскочить до 90%.
6. HPA реагирует снова, добавляя реплики до максимума. 
7. Возникает бесконечный конфликт (thrashing).

**Правильный паттерн использования:**
Можно использовать HPA и VPA вместе, только если они реагируют на **разные метрики**. Например: HPA масштабирует по Custom Metric (количество запросов в секунду RPS), а VPA работает в режиме `Auto` и управляет выделением CPU/Memory под этот объем трафика. Либо HPA скейлит по CPU, а VPA скейлит только Memory (используя `controlledValues: RequestsAndLimits` для конкретных ресурсов).

### 3.3 Практика: Наблюдение за рекомендациями VPA

Так как на нашем стенде VPA-контроллеры не установлены глобально (чтобы не ломать соседние неймспейсы), мы приведем пример того, как выглядит манифест и вывод рекомендаций в реальной жизни.

Манифест VPA:
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: hpa-demo-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: hpa-demo
  updatePolicy:
    updateMode: "Off"  # Безопасный режим рекомендаций
```

Если бы мы применили этот манифест, через некоторое время `kubectl describe vpa hpa-demo-vpa` показал бы:
```yaml
Status:
  Recommendation:
    Container Recommendations:
      Container Name:  php-apache
      Lower Bound:     # Минимальная граница
        Cpu:     10m
        Memory:  25Mi
      Target:          # РЕКОМЕНДОВАННОЕ значение
        Cpu:     150m
        Memory:  50Mi
      Uncapped Target: # Рекомендация без учета ограничений min/max
        Cpu:     150m
        Memory:  50Mi
      Upper Bound:     # Максимальная граница
        Cpu:     1
        Memory:  200Mi
```
Инженер может взять значение `Target` (150m CPU, 50Mi Memory) и прописать его руками в свой Deployment.

---

## Часть 4: Cluster Autoscaler (CA)

### 4.1 Как работает CA (Теория)

**Три уровня автоскейла — что масштабируют и чем триггерятся:**

| Технология | Объект управления | Направление масштабирования | Триггер срабатывания | Скорость реакции |
|---|---|---|---|---|
| **HPA** | `replicas` в Deploy/STS | Горизонтально (+ поды) | Метрики (выше/ниже цели) | Секунды |
| **VPA** | `requests/limits` в Pod | Вертикально (размер пода) | Факт. потребление vs requests | Секунды-Минуты (рестарт) |
| **Cluster Autoscaler** | Количество **НОД** в облаке | Инфраструктура (+ виртуалки) | `Pending` поды / Пустые ноды | Минуты (3-5 мин) |

Cluster Autoscaler (CA) — это системный компонент, который постоянно сканирует кластер. У него две основные задачи:
1. **Scale-Up:** CA ищет поды, которые находятся в состоянии `Pending` из-за ошибки `FailedScheduling` (например, кластер забит под завязку и для нового пода нет свободного CPU/RAM на текущих нодах). CA симулирует планировщик (binpacking simulation), проверяет, поможет ли добавление новой ноды в Cloud Provider, и если да — дает команду облаку (AWS ASG, GCP MIG) создать виртуалку.
2. **Scale-Down:** CA ищет ноды, чья утилизация (сумма requests подов) упала ниже порога (обычно 50%). Если поды с этой ноды можно перенести (evict) на другие существующие ноды, CA запускает процесс drain (эвакуацию ноды) и затем удаляет виртуалку в облаке для экономии денег.

### 4.2 Цепочка HPA → CA

В реальном production-кластере HPA и Cluster Autoscaler работают в неразрывной связке.
**Типичный сценарий при наплыве трафика:**
1. **Нагрузка растет.** Трафик на `hpa-demo` вырастает, CPU взлетает.
2. **HPA реагирует.** HPA видит скачок и увеличивает `replicas` с 5 до 20.
3. **Нехватка ресурсов (Capacity Exhaustion).** Планировщик (`kube-scheduler`) успешно размещает 5 новых подов на существующих нодах. Остальные 10 подов зависают в состоянии `Pending` с ошибкой `Insufficient cpu`.
4. **CA реагирует.** Cluster Autoscaler видит `Pending` поды, понимает, что им не хватает места, и делает API-запрос к AWS/GCP на увеличение `NodePool` с 3 до 5 серверов.
5. **Ожидание IaaS.** В течение 3-5 минут облако провижинит новые виртуалки, они скачивают образы, запускают Kubelet и присоединяются к кластеру.
6. **Размещение.** Ноды становятся `Ready`, `kube-scheduler` размещает на них оставшиеся 10 подов. Приложение спасено.

```bash
# Как выглядит нехватка ресурсов (если HPA раздулся, а CA нет):
kubectl -n lab get pods -l app=hpa-demo --field-selector=status.phase=Pending

# Если CA включен, можно увидеть системные события масштабирования:
kubectl get events -n kube-system | grep -iE "TriggeredScaleUp|NotTriggerScaleUp" | tail -3
# Пример: Normal  TriggeredScaleUp  cluster-autoscaler  pod triggered scale-up: [{pool-1 3->4 (max: 10)}]
```

---

## Часть 5: Продвинутое масштабирование (KEDA, Karpenter, DRA)

Стандартные механизмы (HPA и Cluster Autoscaler) хороши, но имеют архитектурные ограничения. Для более сложных и современных сценариев применяют специализированные инструменты. 

> **Важно:** Эти инструменты не установлены на учебном кластере по умолчанию, так как требуют сложной привязки к Cloud Provider (AWS/GCP) или установки операторов. В директории `manifests/` лежат готовые примеры (CRD) для изучения.

### 5.1 KEDA (Kubernetes Event-driven Autoscaling)

**Проблема стандартного HPA:** 
HPA масштабирует поды на основе метрик (в основном CPU/RAM). Представьте, что ваши поды — это воркеры, которые читают очередь RabbitMQ или Kafka. Если в очереди нет сообщений, вы хотите, чтобы реплик было `0` (Scale to Zero). HPA не умеет масштабировать в 0. Более того, если воркеров `0`, то их CPU потребление равно `0`, и HPA никогда не начнет масштабирование вверх, даже если очередь заполнится тысячами сообщений!

**Решение KEDA:** 
KEDA (CNCF инкубатор) выступает мостом между десятками внешних источников событий (Kafka, SQS, PostgreSQL, Prometheus) и Kubernetes. Он умеет **самостоятельно масштабировать Deployment напрямую от 0 до 1** (наблюдая за источником, а не за подами). Как только реплик становится `1`, KEDA динамически создает стандартный объект HPA и передает ему управление (масштабирование от 1 до N) через Custom Metrics API. При опустошении очереди KEDA снова удаляет HPA и масштабирует Deployment в 0.

```bash
# Пример: Изучите манифест KEDA ScaledObject, который масштабирует
# воркеры от 0 до 10 на основе длины очереди (RabbitMQ)
cat manifests/keda-scaledobject.yaml
```

### 5.2 Karpenter (Оптимизированный Node Provisioning)

**Проблема Cluster Autoscaler (CA):** 
CA работает на уровне абстракций облака — Node Groups / Node Pools (ASG в AWS, MIG в GCP). Он запрашивает у облака "добавь +1 ноду в этот конкретный пул". Если поду нужен инстанс с GPU, а в пуле только CPU-ноды, CA бессилен (если вы заранее не создали отдельный пустой пул для GPU). Кроме того, масштабирование через пулы (ASG) медленное и жестко привязано к конкретным типам машин (instance types).

**Решение Karpenter:** 
Karpenter (создан AWS, передан в CNCF) напрямую общается со слоем IaaS облака (Fleet API), минуя громоздкие группы автомасштабирования (Group-less provisioning). Он "на лету" анализирует `Pending` поды, смотрит на их `requests`, `nodeSelectors`, `tolerations` и запрашивает у облака *идеально подходящую ноду* "прямо сейчас". Если подам суммарно нужно 15 CPU, Karpenter создаст одну ноду на 16 CPU. Если нужно 100 CPU, он может создать две по 64 CPU, выбрав самые дешевые спотовые (Spot) инстансы из десятков доступных типов. Запуск ноды через Karpenter часто занимает менее 30 секунд. Также он умеет агрессивно консолидировать полупустые ноды для экономии средств.

```bash
# Пример: Изучите манифест Karpenter NodePool. 
# Заметьте, что вместо жесткой фиксации m5.large, задаются требования:
# любая AMD64/ARM64 нода, типов C/M/R, спот или он-деманд.
cat manifests/karpenter-nodepool.yaml
```

### 5.3 DRA (Dynamic Resource Allocation)

**Проблема:** В Kubernetes традиционно есть только примитивные ресурсы: `cpu`, `memory` и `ephemeral-storage`. Запрос специфичного "железа" (GPU, FPGA, InfiniBand) требовал установки костыльных плагинов (Device Plugins), которые экспортировали ресурсы типа `nvidia.com/gpu: 1`. Но что если вам нужна ровно "половина GPU"? Или GPU конкретной модели с нужной топологией подключения NUMA? Стандартные Device Plugins этого не умеют.

**Решение DRA:** 
Dynamic Resource Allocation абстрагирует "железо" подобно тому, как PVC/PV абстрагируют диски (Storage). Вы создаете `ResourceClaim` с детальными параметрами (нужна карточка с 16GB VRAM, архитектура Turing), а вендорский контроллер (DRA Driver, например от NVIDIA) динамически её находит, выделяет и пробрасывает в под.

```bash
# Пример: Изучите манифест ResourceClaim
cat manifests/dra-resourceclaim.yaml
```

---

## Часть 6: Troubleshooting (Расширенный)

### Дерево диагностики HPA `<unknown>`

Самая частая ошибка при работе с HPA — увидеть статус `<unknown>` в колонке TARGETS. Это значит, что HPA не смог получить или вычислить метрику. Процесс диагностики:

```text
HPA TARGETS = <unknown>/50% ?
   │
   ├─ 1) kubectl top pods -n lab
   │     ├─ Ошибка "Metrics API not available" ──> НЕТ metrics-server → Инцидент 2
   │     └─ Выводятся числа (CPU/Memory) ──┐
   │                                       ▼
   ├─ 2) У пода задан requests.cpu?
   │     (Проверка: kubectl -n lab get deploy hpa-demo -o jsonpath='{.spec.template.spec.containers[0].resources.requests}')
   │     ├─ Пусто ──> НЕТ requests.cpu (не от чего считать процент) → Инцидент 1
   │     └─ Задано ──┐
   │                 ▼
   ├─ 3) Поды находятся в статусе Running и Ready?  
   │     (Метрики берутся ТОЛЬКО с Ready-подов!)
   │     ├─ Нет ──> Чинить под (CrashLoopBackOff / ErrImagePull) — см. модули 02/08
   │     └─ Да ──┐
   │             ▼
   └─ 4) Под создан только что? 
         ──> Подожди 15-60с. Kubelet собирает метрики раз в 10с, metrics-server агрегирует раз в 15с.
```

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
# TARGETS: <unknown>/50%

# Читаем причину напрямую из HPA Events/Conditions:
kubectl -n lab describe hpa hpa-demo | grep -A3 -iE "unable|FailedGetResourceMetric|missing request"
# Ожидаемый вывод ошибки:
# the HPA was unable to compute the replica count: failed to get cpu utilization:
#   missing request for cpu in container php-apache in pod hpa-demo-84f9...
```

**Решение:**
Необходимо добавить блог `resources.requests.cpu` в спецификацию контейнера.
```bash
kubectl -n lab apply -f solutions/01-no-requests/deploy.yaml   # добавлен requests.cpu
sleep 15
kubectl -n lab get hpa hpa-demo                                 # TARGETS -> 0%/50%
```

### Инцидент 2: HPA не масштабирует — нет metrics-server

**Симптом:** Тот же `<unknown>`, но в манифесте `requests.cpu` точно заданы.
```bash
kubectl top pods -n lab
# error: Metrics API not available
```
**Причина и Решение:** Metrics Server упал или вообще не установлен на кластере. Проверьте поды в `kube-system`: `kubectl get pods -n kube-system -l k8s-app=metrics-server`. Восстановите/установите metrics-server.

### Инцидент 3: Scale-up есть, но поды `Pending`

**Симптом:** HPA работает, значение `REPLICAS` выросло с 1 до 50. Но при проверке подов — они зависли.
```bash
kubectl -n lab get pods -l app=hpa-demo
kubectl -n lab describe pod -l app=hpa-demo | grep -A1 FailedScheduling
# Warning  FailedScheduling  default-scheduler  0/5 nodes are available: 5 Insufficient cpu.
```
**Лечение:** HPA выполнил свою работу идеально (отмасштабировал логику). Проблема в инфраструктуре. Нужно включить Cluster Autoscaler (чтобы он добавил ноды) или руками увеличить пул (Node Pool) в облаке.

### Инцидент 4: Flapping (дребезг) реплик

**Симптом:** Реплики HPA постоянно прыгают: 2 -> 10 -> 2 -> 10 каждые несколько минут.
**Причина:** Поды запускаются медленно. HPA видит высокую загрузку, добавляет поды, но они долго инициализируются (или долго прогревают кэш, жрут CPU на старте). HPA паникует от высокого CPU стартующих подов и добавляет еще реплик. Затем все успокаиваются, CPU падает в ноль, HPA убивает почти все поды. Снова прыжок трафика — цикл повторяется.
**Решение:** Увеличить `stabilizationWindowSeconds` для Scale-up и Scale-down, чтобы дать приложению время "согреться" и стабилизировать метрики.

### Инцидент 5: Ошибка чтения Custom Metrics

**Симптом:** `<unknown>` на HPA, который настроен на масштабирование по `type: External` или `type: Object` (например, количество запросов RPS из Prometheus).
**Причина:** HPA обращается не к `metrics-server` (он обслуживает только CPU/Memory), а к расширению API `custom.metrics.k8s.io`. Обычно за это отвечает адаптер (Prometheus Adapter или KEDA). Если адаптер упал или запрос (PromQL) написан криво — HPA не получит данные.
**Диагностика:** Попробовать получить метрику вручную минуя HPA:
`kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/lab/pods/*/http_requests"`

---

## Проверка модуля

Проверьте, что инфраструктура лаборатории находится в рабочем состоянии:

```bash
# Возвращаем рабочие манифесты
kubectl -n lab apply -f manifests/deploy.yaml -f manifests/svc.yaml -f manifests/hpa.yaml
kubectl -n lab rollout status deploy/hpa-demo --timeout=120s
sleep 30   # дать HPA снять первую метрику

bash verify/verify.sh
# [OK] hpa-demo metric available (current CPU utilization = 0%)
# [OK] module 11 verified
```

Скрипт `verify.sh` проверяет: наличие namespace `lab` → `Deployment/hpa-demo` готов → есть `HPA/hpa-demo` → HPA видит метрику (статус отличен от `<unknown>`). 

---

## Финальная карта ресурсов модуля

| Ресурс | Что демонстрирует |
|--------|-------------------|
| `hpa-demo` (Deployment) | CPU-bound нагрузка; правильное указание `requests.cpu` |
| `hpa-demo` (Service) | Точка входа в кластер для генератора нагрузки |
| `hpa-demo` (HPA v2) | Автоскейл 1→5 по 50% CPU, демонстрация сбора метрик |
| `load` (Pod) | Генератор HTTP-нагрузки (`wget` в цикле) для провокации scale-up |

---

## Теоретические вопросы (итоговые)

1. Выведите формулу желаемых реплик HPA. Как отсутствие `requests.cpu` в манифесте пода ломает эту математику?
2. Назовите объекты масштабирования (что именно они меняют?) для HPA, VPA и Cluster Autoscaler.
3. Объясните причину асимметрии: почему по умолчанию scale-up происходит быстро, а scale-down медленно (задержка 5 минут)? Какое негативное явление это предотвращает?
4. Почему категорически запрещено использовать HPA и VPA в режиме `Auto` на одной и той же метрике (например, CPU)? Опишите цикл конфликта.
5. Назовите две самые частые причины статуса `<unknown>` в TARGETS HPA и как их диагностировать (какие команды `kubectl` использовать).
6. В чем фундаментальное архитектурное преимущество Karpenter перед классическим Cluster Autoscaler (CA)? Что такое group-less provisioning?
7. Какую проблему решает KEDA, которую не может решить стандартный HPA?

---

## Практические задания (отработка)

> Выполняйте задания на живом кластере; проверяйте себя командами диагностики и скриптом `verify/verify.sh`.

1. **Эксперимент со Stabilization Window:** Под нагрузкой (генератор) поймайте scale-up `1→5`; после снятия нагрузки засеките время окна стабилизации scale-down. Измените в `hpa.yaml` окно на 10 секунд и повторите эксперимент. Убедитесь, что поды убиваются быстрее.
2. **Симуляция `<unknown>`:** Воспроизведите инцидент `<unknown>` двумя способами. В первом удалите `requests.cpu` из Deployment. Во втором случае - масштабируйте `metrics-server` в 0 реплик (`kubectl scale deploy metrics-server -n kube-system --replicas=0`). Изучите разницу в логах Events HPA (`kubectl describe hpa`).
3. **Ручной расчет:** Запустите нагрузку так, чтобы HPA стабилизировался на утилизации 80% (на 3 подах). Посчитайте по формуле HPA желаемые реплики при цели 40% и сверьте с поведением кластера после изменения цели через команду `kubectl autoscale`.
4. **Конфликт ресурсов:** Уроните под в статус `Pending`, задав ему астрономический `requests.cpu: "100"`. Объясните, чем в данной ситуации поможет Cluster Autoscaler (и поможет ли, если в облаке нет машин на 100 ядер?).

---

## Шпаргалка

```bash
# === HPA ===
kubectl -n lab get hpa hpa-demo
kubectl -n lab describe hpa hpa-demo                 # Смотреть Events: SuccessfulRescale / FailedGetMetric...
kubectl -n lab get hpa hpa-demo -o jsonpath='{.status.currentMetrics}' # Вытащить сырые цифры метрик
# Императивное создание HPA:
kubectl -n lab autoscale deploy hpa-demo --cpu-percent=50 --min=1 --max=5

# === Нагрузка / наблюдение ===
kubectl -n lab run load --image=busybox:1.36 --restart=Never -- sh -c 'while true; do wget -q -O- http://hpa-demo; done'
kubectl -n lab get hpa hpa-demo -w  # Watch режим
kubectl top pods -n lab             # Прямой опрос metrics-server

# === Troubleshooting / Cluster Autoscaler ===
kubectl get events -n kube-system | grep -iE "TriggeredScaleUp|NotTriggerScaleUp"
# Проверка кастомных метрик:
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1

# === Уборка ===
kubectl -n lab delete pod load --ignore-not-found
kubectl -n lab delete -k manifests/
```

---

## Чему вы научились

В этом расширенном модуле вы глубоко изучили экосистему автомасштабирования Kubernetes:
- **HPA:** Освоили математику контроллера, научились настраивать политики поведения (`behavior`) для защиты от дребезга (flapping), и уверенно диагностируете проблемы с отсутствующими метриками.
- **VPA:** Разобрали компонентную архитектуру (Recommender, Updater, Admission), поняли ограничения иммутабельности ресурсов и усвоили правило избегания конфликтов HPA+VPA.
- **Infrastructure Scaling:** Изучили разницу между классическим пуловым масштабированием (Cluster Autoscaler) и современным беспублированным подходом (Karpenter).
- **Событийное масштабирование:** Узнали о существовании KEDA и его способности масштабировать рабочие нагрузки до нуля.

Эти навыки критически важны для проектирования отказоустойчивых и экономически эффективных кластеров в Production-средах.

## Уборка

```bash
kubectl -n lab delete pod load --ignore-not-found
kubectl -n lab delete deploy,svc,hpa,vpa --all --ignore-not-found
```


## Решения (Solutions)
В данном модуле добавлены подробные решения для сломанных сценариев в папке `solutions/`. Пожалуйста, изучите их для лучшего понимания.
