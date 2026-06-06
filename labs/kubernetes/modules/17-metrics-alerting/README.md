# Лабораторная работа 17: Метрики и алертинг (Prometheus + Grafana + Alertmanager)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Установка kube-prometheus-stack](#-1--kube-prometheus-stack)
  - [Теория для изучения перед частью](#----)
  - [1.1 helm install](#11-helm-install)
- [Часть 2: PromQL](#-2-promql)
  - [Теория для изучения перед частью](#----)
  - [2.1 Запросы](#21-)
- [Часть 3: ServiceMonitor — подключить своё приложение](#-3-servicemonitor----)
  - [Теория для изучения перед частью](#----)
  - [3.1 ServiceMonitor → таргет](#31-servicemonitor--)
- [Часть 4: Grafana и алерты](#-4-grafana--)
  - [Теория для изучения перед частью](#----)
  - [4.1 Grafana](#41-grafana)
  - [4.2 Алерт](#42-)
- [Часть 5: Troubleshooting](#-5-troubleshooting)
  - [Инцидент 1: таргет не появляется (ServiceMonitor без `release` label)](#-1----servicemonitor--release-label)
  - [Инцидент 2: таргет есть, но `up == 0` (NetworkPolicy блокирует scrape)](#-2----up--0-networkpolicy--scrape)
  - [Инцидент 3: PromQL даёт пустой результат](#-3-promql---)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~30 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)

Цель: поднять полноценный observability-стек и научиться им пользоваться —
собирать метрики (Prometheus), запрашивать их (PromQL), визуализировать
(Grafana), подключать свои приложения (ServiceMonitor) и заводить алерты
(PrometheusRule + Alertmanager). Это развитие модуля 08 (там был только
`kubectl top`) до настоящего стека с историей и алертами.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
helm version --short    # нужен Helm
kubectl get nodes       # нужны рабочие ноды (стек заметно потребляет RAM)
```

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

---

## Часть 1: Установка kube-prometheus-stack

### Теория для изучения перед частью

- **Prometheus** — pull-модель: сам ходит и скрейпит `/metrics` целей по
  расписанию, хранит time-series, отвечает на PromQL. В отличие от
  metrics-server (только текущие CPU/RAM), Prometheus хранит ИСТОРИЮ.
- **kube-prometheus-stack** ставит разом: Prometheus + **Grafana** (дашборды) +
  **Alertmanager** (маршрутизация алертов) + **node-exporter** (метрики нод) +
  **kube-state-metrics** (метрики объектов k8s) + **prometheus-operator**
  (управляет всем через CRD).

**Pull vs push:**

| | Pull (Prometheus) | Push (StatsD/Graphite) |
|---|---|---|
| Кто инициирует | Prometheus САМ ходит на `/metrics` | приложение ШЛЁТ в коллектор |
| Где список целей | service discovery (k8s API) | приложение знает адрес коллектора |
| «Жив ли таргет» | видно даром (`up=0`, если не доскрейпил) | тишина = непонятно (умер? нет нагрузки?) |
| Кому | долгоживущие сервисы | короткие задачи (через Pushgateway как мост) |

**Архитектура стека (кто кого скрейпит и куда течёт):**

```
node-exporter (DaemonSet, метрики НОД) ──┐
kube-state-metrics (объекты k8s)        ─┤ scrape (pull, /metrics)
твой app + ServiceMonitor               ─┘            │
                                                       ▼
prometheus-operator ──(настраивает по CRD)──>  PROMETHEUS  (TSDB + PromQL + eval правил)
                                                  │                          │
                                          Grafana (дашборды) ◄───────┐   алерт Firing
                                                                     │       ▼
                                                          datasource │   Alertmanager ──> Slack/email/PagerDuty
```

---

**Цель:** установить стек и увидеть его компоненты.

---

### 1.1 helm install

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace --wait

kubectl -n monitoring get pods
# kps-grafana-...                        Running
# kps-kube-prometheus-stack-operator-... Running
# prometheus-kps-...-0                   Running   (сам Prometheus, StatefulSet)
# alertmanager-kps-...-0                 Running
# kps-kube-state-metrics-...             Running
# kps-prometheus-node-exporter-... (DaemonSet, по поду на ноду)
```

**Контрольные вопросы:**
1. Чем pull-модель Prometheus отличается от push?
2. За что отвечают node-exporter и kube-state-metrics?
3. Чем Prometheus принципиально полнее metrics-server?

---

## Часть 2: PromQL

### Теория для изучения перед частью

- PromQL: селекторы по labels (`up{job="..."}`), функции (`rate`, `sum`, `avg`),
  агрегация `by (label)`. `rate(counter[1m])` — скорость роста за минуту.

- **Instant vector vs range vector** (фундамент PromQL):
  - **instant vector** — по ОДНОМУ значению на серию в момент времени: `up`,
    `node_memory_MemAvailable_bytes`. Это можно строить на графике напрямую.
  - **range vector** — РЯД значений за окно `[5m]`: `node_network_receive_bytes_total[5m]`.
    Напрямую НЕ строится — только через функцию, что свернёт окно в число
    (`rate(...[5m])`, `increase(...[5m])`). Частая ошибка — построить голый `[5m]`.

- **Типы метрик и какие функции к ним:**

| Тип | Поведение | Реальная метрика в кластере | Функция |
|-----|-----------|------------------------------|---------|
| **counter** | только растёт (сброс при рестарте) | `node_network_receive_bytes_total` | `rate()`/`increase()` |
| **gauge** | вверх и вниз | `node_memory_MemAvailable_bytes` | напрямую / `avg`/`max` |
| **histogram** | бакеты `_bucket` + `_sum`/`_count` | `apiserver_request_duration_seconds_bucket` | `histogram_quantile(0.95, ...)` |
| **summary** | предвычисленные квантили | `..._sum` / `..._count` | `rate(sum)/rate(count)` |

#### rate() vs irate() — сглаживание против резкости

Обе считают «скорость роста counter за окно», но по-разному выбирают точки:

| | `rate(c[5m])` | `irate(c[5m])` |
|---|---|---|
| По каким точкам | по ВСЕМ точкам окна (усреднение) | только по ДВУМ последним в окне |
| Поведение | сглаженный тренд | мгновенная, «дёрганая» скорость |
| Реакция на всплеск | размазывает по окну | ловит, но шумит |
| Где применять | **алерты и графики** (стабильность) | дебаг короткого всплеска вручную |

- Эмпирика: окно `[Nm]` бери ≥ 4× scrape-интервала (у нас scrape ~30с ⇒ окно
  `[2m]` и больше), иначе rate «промахивается» между точками и даёт дыры.
- `rate`/`irate` корректно переживают **сброс counter** при рестарте процесса
  (детектируют падение значения и не дают отрицательную скорость).

#### Проблема кардинальности (cardinality) — почему Prometheus падает по памяти

**Кардинальность = число уникальных временных рядов** (одна комбинация
`__name__` + всех label-значений = один ряд в TSDB, держится в RAM). Каждый
новый набор меток порождает НОВЫЙ ряд. Метрика с меткой высокой мощности
(`user_id`, `request_id`, `pod` в крупном кластере) взрывает память.

**Reality на нашем Prometheus** (kube-prometheus-stack):

```bash
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
# Всего активных рядов в head-блоке:
curl -s 'http://localhost:9090/api/v1/query?query=prometheus_tsdb_head_series'
#   ~81 569 рядов

# Топ метрик по числу рядов (вкладка Status → TSDB Status, или API):
curl -s http://localhost:9090/api/v1/status/tsdb   # seriesCountByMetricName
#   apiserver_request_body_size_bytes_bucket   7200   <- гистограмма-лидер
#   apiserver_request_duration_seconds_bucket  6680
#   etcd_request_duration_seconds_bucket       4380
# Топ меток по числу значений (labelValueCountByLabelName):
#   __name__ 2127,  name 873,  le 336,  resource 334
```

> Что показывают числа: топ по рядам — **гистограммы** (`_bucket`). У гистограммы
> ряды множатся как `кол-во le-бакетов × verb × resource × code` — отсюда 7200
> рядов у ОДНОЙ метрики. Метка `le` сама даёт 336 значений. Вывод-правило:
> **не клади в метрику метку с неограниченным числом значений** (id запроса,
> email, полный URL). Лечится `metric_relabel_configs` (drop лишних меток на
> scrape) и осторожностью с гистограммами. `Status → TSDB Status` в UI — первое,
> куда смотреть, когда Prometheus раздувается по RAM или OOMKilled.

---

**Цель:** выполнить запросы в Prometheus UI.

---

### 2.1 Запросы

```bash
# Проброс Prometheus UI на localhost:9090
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
sleep 2

# Через API (или вкладка Graph в UI http://localhost:9090):
curl -s 'http://localhost:9090/api/v1/query?query=up' | head -c 200
# {"status":"success",...,"value":[...,"1"]}   <- живые таргеты

# Полезные запросы:
#   up                                              — все цели (1=жива)
#   sum(rate(http_requests_total[1m]))              — rate запросов
#   kube_pod_status_phase{namespace="lab"}          — фазы подов (kube-state-metrics)
#   node_memory_MemAvailable_bytes                  — память нод (node-exporter)
kill %1 2>/dev/null
```

**Контрольные вопросы:**
1. Чем counter отличается от gauge и зачем `rate()`?
2. Что вернёт `up` и как найти упавший таргет?
3. Как агрегировать метрику по namespace через `by`?

---

## Часть 3: ServiceMonitor — подключить своё приложение

### Теория для изучения перед частью

- Prometheus-operator управляется через CRD: **ServiceMonitor** (скрейпить
  Service), **PodMonitor** (скрейпить поды напрямую), **PrometheusRule** (алерты/
  recording). Объявил CRD — оператор сам перенастроил Prometheus.

**Цепочка связывания (каждое звено должно «сойтись» по label):**

```
Pod (label app=metrics-app, порт :8080)
   ▲ Service.spec.selector {app: metrics-app}, port name=metrics
Service ──────────────────────────────┐
   ▲ ServiceMonitor.spec.selector.matchLabels {app: metrics-app} + endpoints.port=metrics
ServiceMonitor (label release=kps) ────┤
   ▲ Prometheus.spec.serviceMonitorSelector.matchLabels {release: kps}
Prometheus (создан оператором) ── оператор генерит scrape_config ── скрейпит Endpoints
```

> **Откуда берётся `release: kps`.** Стек ставится helm-релизом с ИМЕНЕМ `kps`
> (`helm install` **`kps`** `.../kube-prometheus-stack`). Чарт прописывает своему
> Prometheus `serviceMonitorSelector: { matchLabels: { release: kps } }` (где
> `kps` = имя релиза). Поэтому ТВОЙ ServiceMonitor обязан нести label
> `release: kps` — иначе именно этот Prometheus его проигнорирует (Инцидент 1).
> Поставил бы стек как `helm install foo` — селектор был бы `release: foo`.

---

**Цель:** подключить demo-приложение к Prometheus.

**Ресурсы:** `manifests/app.yaml` + `servicemonitor.yaml` + `prometheusrule.yaml`.

---

### 3.1 ServiceMonitor → таргет

```bash
kubectl -n lab apply -f manifests/app.yaml
kubectl -n lab rollout status deploy/metrics-app --timeout=120s
kubectl -n lab apply -f manifests/servicemonitor.yaml manifests/prometheusrule.yaml

# Через ~30с таргет metrics-app появится UP:
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
sleep 3
curl -s 'http://localhost:9090/api/v1/query?query=up{job="metrics-app"}' | grep -o '"value":\[[^]]*\]'
# "value":[...,"1"]   <- наш таргет скрейпится
kill %1 2>/dev/null
```

**Контрольные вопросы:**
1. Что делает ServiceMonitor и кто его «исполняет»?
2. Почему ServiceMonitor нужен label `release: kps`?
3. Чем PodMonitor отличается от ServiceMonitor?

---

## Часть 4: Grafana и алерты

### Теория для изучения перед частью

- **Grafana** строит дашборды на основе datasource (Prometheus уже подключён в
  стеке) — kube-prometheus-stack привозит готовые дашборды (ноды, поды, кластер).
- **Alertmanager** принимает сработавшие алерты от Prometheus и маршрутизирует
  (группировка, заглушки, получатели: Slack/email/PagerDuty).
- **PrometheusRule** содержит `alert` (условие + `for` + labels/annotations) и
  `record` (предвычисленные ряды).

**Жизненный цикл алерта (где какое состояние):**

```
PrometheusRule.alert (expr)  ── Prometheus вычисляет каждые ~15-30с
        │
   expr ложно ──> Inactive
   expr истинно ──> Pending  ── держится ВЕСЬ `for: 1m`? ──> Firing
        │                          (если expr успело стать ложным — назад в Inactive)
        ▼
   Firing ──> Alertmanager:
        group_by (склейка похожих) ──> routing tree (по labels -> receiver)
        silences / inhibition могут ПОДАВИТЬ ──> Slack / email / PagerDuty
```

> `for` гасит «дребезг»: алерт не летит на единичный всплеск, а только если условие
> держится всё окно. Состояние видно в Prometheus UI (Status → Alerts: Inactive/
> Pending/Firing), маршрутизация и заглушки — в Alertmanager UI.

---

### 4.1 Grafana

```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80 &
# http://localhost:3000  (admin / admin) -> Dashboards: Kubernetes / Compute Resources
kill %1 2>/dev/null
```

### 4.2 Алерт

```bash
# Правило MetricsAppDown уже применено (prometheusrule.yaml). Проверим, что
# Prometheus его видит (Status -> Rules или API):
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
sleep 2
curl -s 'http://localhost:9090/api/v1/rules' | grep -o 'MetricsAppDown' | head -1
kill %1 2>/dev/null
# Если уронить metrics-app (replicas=0) -> через 1м алерт перейдёт в Firing.
```

**Контрольные вопросы:**
1. Откуда Grafana берёт данные и что такое datasource?
2. Что делает Alertmanager после срабатывания алерта в Prometheus?
3. Из чего состоит правило `alert` и зачем поле `for`?

---

## Часть 5: Troubleshooting

### Инцидент 1: таргет не появляется (ServiceMonitor без `release` label)

Разобран в `broken/scenario-01/`. Суть: Prometheus берёт ServiceMonitor только с
label `release: kps`; без него таргета нет. Лечение —
`kubectl -n lab label servicemonitor metrics-app release=kps`.

### Инцидент 2: таргет есть, но `up == 0` (NetworkPolicy блокирует scrape)

Самый коварный: таргет ВИДЕН в Prometheus, но `up{job="metrics-app"} == 0` —
скрейп не доходит. На кластере с enforced NetworkPolicy (Calico) частая причина —
`default-deny` в namespace приложения: Prometheus (под из `monitoring`) не может
достучаться до `/metrics`. Лечение — разрешить ingress к приложению от namespace
`monitoring`:

```yaml
# ingress к metrics-app от подов из monitoring
spec:
  podSelector: { matchLabels: { app: metrics-app } }
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: monitoring } }
    ports: [{ protocol: TCP, port: 8080 }]
```

> Проверено вживую: пока в `lab` висел `default-deny` из модуля 15, `up` был `0`;
> после снятия политик (или добавления allow от `monitoring`) — `up` стал `1`.

### Инцидент 3: PromQL даёт пустой результат

```bash
# Частые причины: опечатка в имени метрики/label, метрика ещё не собрана,
# неверный job. Проверить, какие вообще метрики есть:
# в UI: начните вводить имя — автодополнение; или /api/v1/label/__name__/values
```

**Контрольные вопросы:**
1. Таргет не появился — где смотреть `serviceMonitorSelector` и что добавить?
2. PromQL пуст — три возможные причины?
3. Как узнать список доступных метрик?

---

## Проверка модуля

```bash
kubectl -n lab apply -f manifests/app.yaml
kubectl -n lab apply -f manifests/servicemonitor.yaml
kubectl -n lab rollout status deploy/metrics-app --timeout=120s

bash verify/verify.sh
# [OK] kube-prometheus-stack present (ns monitoring)
# [OK] module 17 verified
```

`verify.sh`: namespace `lab` → `metrics-app` готов → есть `ServiceMonitor/metrics-app`
→ установлен kube-prometheus-stack (ns monitoring + Prometheus). Если стек не
установлен — мягкий `[WARN]`.

---

## Финальная карта ресурсов модуля

| Ресурс | Что демонстрирует |
|--------|-------------------|
| kube-prometheus-stack (ns monitoring) | Prometheus/Grafana/Alertmanager/exporters |
| `metrics-app` (Deployment+Service) | приложение, экспортящее `/metrics` |
| `metrics-app` (ServiceMonitor) | декларативное подключение к Prometheus |
| `metrics-app-rules` (PrometheusRule) | recording-rule + alert MetricsAppDown |

---

## Теоретические вопросы (итоговые)

1. Опишите архитектуру kube-prometheus-stack (роль каждого компонента) и pull vs push.
2. Чем counter/gauge/histogram отличаются и какие функции PromQL к ним? Чем instant
   vector отличается от range vector?
3. Как ServiceMonitor связывает ваше приложение с Prometheus? Откуда берётся
   требование label `release: kps`?
4. Опишите жизненный цикл алерта Inactive→Pending→Firing. Зачем поле `for`?
5. Что делает Alertmanager (group_by/routing/silences) и чем он отличается от Prometheus?
6. Чем этот стек полнее, чем metrics-server из модуля 08?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Подключите своё приложение через ServiceMonitor (label `release: kps`) и найдите его target `up=1`.
2. Воспроизведите «target не появился» (нет label `release: kps`) и почините.
3. Напишите PromQL с `rate(counter[5m])` и `histogram_quantile`; покажите разницу instant vs range vector.
4. Заведите PrometheusRule-алерт с `for: 1m`, уроните приложение и проследите Inactive→Pending→Firing.
5. Найдите в Grafana дашборд по нодам/подам и сопоставьте с `kubectl top`.

---

## Шпаргалка

```bash
# === Стек ===
kubectl -n monitoring get pods,svc
kubectl -n monitoring get prometheus,servicemonitor,prometheusrule -A

# === Доступ ===
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090
kubectl -n monitoring port-forward svc/kps-grafana 3000:80      # admin/admin

# === PromQL (через API) ===
curl -s 'http://localhost:9090/api/v1/query?query=up' 
curl -s 'http://localhost:9090/api/v1/targets' | grep -o '"health":"[a-z]*"'

# === Своё приложение ===
kubectl -n lab apply -f manifests/                 # app + ServiceMonitor + Rule
kubectl -n monitoring get servicemonitor -A | grep metrics-app

# === Уборка ===
kubectl -n lab delete -k manifests/
# helm uninstall kps -n monitoring   # снести весь стек
```

---


## Чему вы научились

В этом модуле вы научились:
- Развёртыванию kube-prometheus-stack
- Сбору метрик приложений через ServiceMonitor
- Настройке правил алертинга в Prometheus/Alertmanager

## Уборка

```bash
kubectl -n lab delete -k manifests/
# полностью снести стек (если больше не нужен):
# helm uninstall kps -n monitoring && kubectl delete ns monitoring
```
