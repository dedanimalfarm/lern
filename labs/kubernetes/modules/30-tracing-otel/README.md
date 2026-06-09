# Лабораторная работа 30: Распределённый трейсинг — OpenTelemetry, Tempo и корреляция с логами

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Span, trace и первый трейс в Tempo](#-1-span-trace-----tempo)
  - [Теория для изучения перед частью](#----)
  - [1.1 Деплой Tempo и синтетический трейс](#11--tempo---)
  - [1.2 Поиск: TraceQL через search API](#12--traceql--search-api)
- [Часть 2: OTel Collector — конвейер телеметрии](#-2-otel-collector---)
  - [Теория для изучения перед частью](#----)
  - [2.1 Деплой коллектора и трафик через него](#21------)
- [Часть 3: Автоинструментация приложения и распределённый trace](#-3-----trace)
  - [Теория для изучения перед частью](#----)
  - [3.1 Деплой и распределённый трейс](#31----)
  - [3.2 TraceQL: ищем ошибки](#32-traceql--)
- [Часть 4: Grafana — единое окно: трейсы ↔ логи](#-4-grafana------)
  - [Теория для изучения перед частью](#----)
  - [4.1 Подключение datasource'ов](#41--datasource)
  - [4.2 Корреляция в обе стороны](#42----)
- [Часть 5: Troubleshooting](#-5-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: трейсы пропали (экспорт в query-порт)](#-1-----query-)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~35 мин · сложность 4/5 · пререквизиты: модули 08, 17, 18

Цель: достроить третий сигнал наблюдаемости. Метрики (модуль 17) отвечают «ЧТО
сломалось», логи (модуль 18) — «ПОЧЕМУ», а **трейсы** — «ГДЕ в цепочке сервисов»
и «в каком порядке». К концу модуля вы поднимаете полный конвейер
**приложение → OTel Collector → Tempo → Grafana**, читаете распределённый trace
из 4 спанов двух сервисов, ищете ошибки через **TraceQL** и связываете трейсы с
логами Loki **в обе стороны** по `trace_id`.

> Все «ожидаемые выводы» сняты на нашем Kubespray (k8s **v1.36.1**):
> Tempo **3.0.2**, OTel Collector contrib **0.153.0**, opentelemetry-python
> **1.42.1/0.63b1**. Модуль 18 называется «logs-tracing», но трассировки там не
> было — она требовала OTel-конвейера. Этот модуль закрывает долг.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# Нужны работающие стеки модулей 17 и 18:
kubectl -n monitoring get deploy kps-grafana          # Grafana (модуль 17)
kubectl -n lab get deploy loki                        # Loki    (модуль 18)
kubectl -n lab get ds promtail                        # Promtail(модуль 18)
```

> **Бюджет квоты.** Модуль живёт в ns `lab` рядом со стеком модуля 18 и сжат
> под ResourceQuota (`requests.memory: 1Gi`, `limits.cpu: 2`): суммарно после
> деплоя занято ~`1820m/2` limits.cpu и ~`912Mi/1Gi` requests.memory. Поэтому
> у всех Deployment'ов модуля `strategy: Recreate` — surge-под RollingUpdate
> в квоту уже не помещается (это не баг, а сознательный трейд-офф; механика —
> в модуле 12).

---

## Стартовая проверка

```bash
kubectl -n lab get deploy tempo otel-collector 2>&1 | head -2   # ещё нет — ок
```

---

## Часть 1: Span, trace и первый трейс в Tempo

### Теория для изучения перед частью

- **Span** — единица работы (HTTP-запрос, SQL-запрос, ручной участок кода) с
  началом, длительностью, статусом и атрибутами. **Trace** — дерево спанов с
  общим `trace_id` (16 байт). Родство задаёт `parent_span_id`.
- **W3C Trace Context** — стандарт переноса контекста между сервисами: заголовок
  `traceparent: 00-<trace_id>-<parent_span_id>-<flags>`. Его ставит и читает SDK
  — приложению ничего делать не нужно.
- **OTLP** — протокол доставки телеметрии (gRPC `:4317` / HTTP `:4318`).
  Единый для трейсов, метрик и логов.
- **Tempo** — бэкенд хранения трейсов от Grafana. Дёшев, потому что не строит
  полнотекстовых индексов: хранит блоки (Parquet) и ищет по ним TraceQL'ем.
  У Tempo **два разных порта**: OTLP ingest (`4317/4318`) и HTTP query API
  (`3200`) — путать их нельзя (Часть 5 посвящена именно этой аварии).
- **Tempo 3.0**: легаси-блоки `ingester:`/`compactor:` из туториалов 2.x
  **удалены** из конфига (новая ingest-архитектура). Со старым конфигом под
  падает в CrashLoopBackOff:
  ```
  failed parsing config: ... line 15: field ingester not found in type app.Config
  ```
  Для миграции боевых конфигов есть `tempo-cli migrate config`.

---

**Цель:** Tempo принимает спаны, search их находит.

**Ресурсы:** `manifests/tempo.yaml`, `extras/telemetrygen-direct.yaml`.

---

### 1.1 Деплой Tempo и синтетический трейс

```bash
kubectl apply -f manifests/tempo.yaml
kubectl -n lab rollout status deploy/tempo --timeout=120s
kubectl -n lab logs deploy/tempo --tail=1 | head -1
# level=info ... msg="Tempo started"

# Первый трейс — синтетикой, без приложений (изолируем механику OTLP→бэкенд):
kubectl create -f extras/telemetrygen-direct.yaml
kubectl -n lab wait --for=condition=complete job/telemetrygen-direct --timeout=120s
kubectl -n lab get job telemetrygen-direct
# NAME                  STATUS     COMPLETIONS   DURATION
# telemetrygen-direct   Complete   1/1           16s
```

### 1.2 Поиск: TraceQL через search API

```bash
# {resource.service.name="telemetrygen"} в urlencode:
kubectl -n lab exec deploy/tempo -- wget -qO- \
  'http://localhost:3200/api/search?q=%7Bresource.service.name%3D%22telemetrygen%22%7D&limit=3'
# {"traces":[{"traceID":"23977a63e931c65ca0763e9b639b6fe0",
#   "rootServiceName":"telemetrygen","rootTraceName":"lets-go", ...
```

> **Tempo 3.0:** легаси-параметр `?tags=service.name%3D...` больше **не
> фильтрует** (молча возвращает всё/ничего). Единственный правильный язык
> поиска — **TraceQL**: `?q={resource.service.name="telemetrygen"}`.

**Контрольные вопросы:**
1. Чем trace_id отличается от span_id и кто порождает оба?
2. Почему у Tempo приём и поиск — разные порты?
3. Что сломается в конфиге 2.x при переходе на Tempo 3.0?

---

## Часть 2: OTel Collector — конвейер телеметрии

### Теория для изучения перед частью

- Tempo умеет принимать OTLP напрямую — **зачем коллектор?** Он развязывает
  приложения и бэкенд:
  - **батчинг** (меньше RPC) и **memory_limiter** (сброс данных вместо OOMKill);
  - обогащение атрибутами (k8s-метаданные), семплинг, фильтрация;
  - **fan-out** в несколько бэкендов и смена бэкенда **без переконфигурации
    приложений** — они знают только адрес коллектора.
- Конфиг = пайплайн: `receivers` (вход) → `processors` (по порядку!) →
  `exporters` (выход), связанные в `service.pipelines.traces`.
- `debug`-exporter печатает каждый батч в stdout — это «щуп» точки
  «до коллектора дошло».
- Коллектор читает конфиг **только при старте**: поменяли ConfigMap → нужен
  `rollout restart`.

---

**Цель:** спаны идут через коллектор; в его логах видно прохождение батчей.

**Ресурсы:** `manifests/otel-collector.yaml`, `extras/telemetrygen-via-collector.yaml`.

---

### 2.1 Деплой коллектора и трафик через него

```bash
kubectl apply -f manifests/otel-collector.yaml
kubectl -n lab rollout status deploy/otel-collector --timeout=120s

kubectl create -f extras/telemetrygen-via-collector.yaml
kubectl -n lab wait --for=condition=complete job/telemetrygen-via-collector --timeout=120s

# debug exporter: каждый принятый батч печатается в stdout коллектора
kubectl -n lab logs deploy/otel-collector --tail=30 | grep -B1 "resource spans"
# ...TracesExporter {"otelcol.component.id": "debug", ... "resource spans": 1, "spans": 10}
```

**Контрольные вопросы:**
1. Почему `memory_limiter` должен стоять ПЕРВЫМ в списке процессоров?
2. Какие два пути доставки видел Tempo в Частях 1–2 и чем они отличаются?
3. Как применить изменение конфига коллектора? (apply CM + rollout restart)

---

## Часть 3: Автоинструментация приложения и распределённый trace

### Теория для изучения перед частью

- **Zero-code инструментация Python:** `opentelemetry-instrument python app.py`
  на старте процесса патчит установленные библиотеки (Flask, requests, logging):
  входящий HTTP-запрос → SERVER-спан, исходящий `requests.get()` → CLIENT-спан
  + заголовок `traceparent` в запрос. Серверный спан второго сервиса становится
  ребёнком клиентского — trace «склеился».
- **Ручные спаны** — для участков, которые автоматика не видит (поход в БД,
  тяжёлая функция): `with tracer.start_as_current_span("db-query")`.
- Конфигурация SDK — через env (`OTEL_SERVICE_NAME`,
  `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_TRACES_EXPORTER=otlp`, семплер —
  `OTEL_TRACES_SAMPLER`, по умолчанию `parentbased_always_on`).
- В лабе код сервисов лежит в ConfigMap, зависимости ставятся pip'ом на старте
  (~1–3 мин): нет registry, зато виден весь инструментируемый код. Версии
  запинены в `requirements.txt` (сняты с живого прогона).

---

**Цель:** один запрос → один trace из 4 спанов двух сервисов; поиск ошибок TraceQL.

**Ресурсы:** `manifests/backend.yaml`, `manifests/frontend.yaml`, `manifests/loadgen.yaml`.

---

### 3.1 Деплой и распределённый трейс

```bash
kubectl apply -f manifests/backend.yaml -f manifests/frontend.yaml -f manifests/loadgen.yaml
kubectl -n lab rollout status deploy/backend --timeout=360s     # pip install внутри
kubectl -n lab rollout status deploy/frontend --timeout=360s

# Запрос руками (loadgen и так шлёт каждые 2с):
kubectl -n lab exec deploy/frontend -- wget -qO- http://localhost:5000/
# {"quote":"W3C traceparent склеивает сервисы в один trace"}

sleep 10   # SDK batch (~5s) + collector batch (2s) + ingest

# Найти трейс и раскрыть его целиком:
kubectl -n lab exec deploy/frontend -- wget -qO- \
  'http://tempo:3200/api/search?q=%7Bresource.service.name%3D%22frontend%22%7D&limit=1'
# {"traces":[{"traceID":"82c49c03af9262717d75f64aca12044","rootServiceName":"frontend",
#   "rootTraceName":"GET /","durationMs":242, ...
kubectl -n lab exec deploy/frontend -- wget -qO- \
  'http://tempo:3200/api/traces/82c49c03af9262717d75f64aca12044'
```

Дерево спанов этого трейса (снято с живого кластера):

```
frontend   GET /              SPAN_KIND_SERVER    scope=...instrumentation.flask
frontend   GET                SPAN_KIND_CLIENT    scope=...instrumentation.requests   ← traceparent ушёл
backend    GET /api/quote     SPAN_KIND_SERVER    scope=...instrumentation.flask      ← traceparent принят
backend    db-query           SPAN_KIND_INTERNAL  scope=backend.manual                ← ручной спан
```

### 3.2 TraceQL: ищем ошибки

```bash
# ~10% запросов backend «падают» симулированной ошибкой БД:
kubectl -n lab exec deploy/frontend -- wget -qO- \
  'http://tempo:3200/api/search?q=%7Bstatus%3Derror%7D&limit=3'
# {"traces":[{"traceID":"bd417386...","rootServiceName":"frontend", ...
#   "attributes":[{"key":"status","value":{"stringValue":"error"}}] ...
```

**Контрольные вопросы:**
1. Кто поставил заголовок `traceparent` в запрос frontend→backend?
2. Почему спанов 4, а не 2? Какие создала автоматика, какой — код?
3. Как найти все медленные трейсы? (TraceQL: `{duration > 300ms}`)

---

## Часть 4: Grafana — единое окно: трейсы ↔ логи

### Теория для изучения перед частью

- Datasource'ы Grafana из модулей 17/18 провижинятся сайдкаром
  `grafana-sc-datasources`: он ловит Secret с лейблом `grafana_datasource: "1"`,
  пишет файл и дёргает reload API.
- **Лог → трейс:** `derivedFields` в datasource Loki — regex вытаскивает
  `trace_id=<32 hex>` из строки лога и рисует ссылку в Tempo. trace_id в логи
  подставляет `OTEL_PYTHON_LOG_CORRELATION=true` (нужен пакет
  `opentelemetry-instrumentation-logging` — в `distro` он НЕ входит).
- **Трейс → логи:** `tracesToLogsV2` в datasource Tempo — кнопка «Logs for this
  span» строит запрос в Loki по времени спана и trace_id.
- Для взаимных ссылок **uid обоих datasource фиксируются** в provisioning
  (`uid: tempo`, `uid: loki`) — на автогенерённый uid сослаться нельзя.
- **Грабли Grafana:** поменять uid уже запровиженного datasource нельзя —
  reload падает 500 `Datasource provisioning error: data source not found`
  (и блокирует ВСЕ остальные файлы, Tempo тоже не появится). Декларативное
  лечение — `deleteDatasources:` перед `datasources:` (есть в
  `loki-datasource-v2.yaml`).

---

**Цель:** Tempo-datasource в Grafana; ссылки лог↔трейс работают в обе стороны.

**Ресурсы:** `manifests/tempo-datasource.yaml`, `manifests/loki-datasource-v2.yaml`.

---

### 4.1 Подключение datasource'ов

```bash
kubectl apply -f manifests/tempo-datasource.yaml -f manifests/loki-datasource-v2.yaml
sleep 60   # сайдкар: watch секрета → запись файла → reload

kubectl -n monitoring logs deploy/kps-grafana -c grafana-sc-datasources --tail=3 | grep -v Loading
# {"msg": "Writing /etc/grafana/provisioning/datasources/loki-datasource.yaml (binary)"}
# {"msg": "... /api/admin/provisioning/datasources/reload. Response: 200 OK ..."}

GPASS=$(kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl -n monitoring port-forward svc/kps-grafana 3909:80 >/dev/null 2>&1 &
curl -s -u "admin:$GPASS" http://localhost:3909/api/datasources | python3 -m json.tool | grep -E '"name"|"uid"'
# "name": "Loki",   "uid": "loki"
# "name": "Tempo",  "uid": "tempo"   (+ Prometheus, Alertmanager из модуля 17)
```

### 4.2 Корреляция в обе стороны

Лог с trace_id (это же увидите в Grafana → Explore → Loki,
`{app="frontend"} |= "backend answered"`):

```
2026-06-09 21:50:56,874 INFO [frontend] [app.py:30]
  [trace_id=1ced788c2a1991635ed30b7de0af94d4 span_id=d3df47dff8b6012a
   resource.service.name=frontend trace_sampled=True] - backend answered: status=200
```

- В раскрытой строке лога поле **TraceID** получает кнопку «Трейс в Tempo» —
  открывает split view с этим трейсом.
- В спане backend в Tempo — кнопка **Logs for this span** → логи Loki этого
  trace_id за окно ±5 минут.

> Строки **вне** активного спана (например, access-log werkzeug пишется после
> завершения спана) содержат `trace_id=0` — поэтому regex derivedFields требует
> ровно 32 hex-символа и на таких строках ссылку не рисует.

**Контрольные вопросы:**
1. Какой пакет добавляет trace_id в логи Python и почему его нет в distro?
2. Зачем фиксировать uid datasource'ов в provisioning?
3. Что делает `deleteDatasources` и когда без него не обойтись?

---

## Часть 5: Troubleshooting

### Теория: диагностика по симптому

```
Симптом: «трейсы пропали / не появляются»
├─ Под приложения не Ready ────────► pip install ещё идёт (startupProbe до 5 мин)
│     kubectl -n lab get pod; describe pod (startup failure?)
├─ В логах приложения ошибки экспорта ─► неверный OTEL_EXPORTER_OTLP_ENDPOINT
│     (должен быть http://otel-collector:4317)
├─ debug-exporter коллектора МОЛЧИТ ───► спаны не доходят до коллектора:
│     Service/порт/endpoint приложения; OTEL_TRACES_EXPORTER=none?
├─ debug печатает, Tempo пуст ─────────► разрыв коллектор→Tempo (Сценарий 01):
│     ищи «Exporting failed» в логах коллектора; проверь exporter endpoint
├─ Tempo CrashLoopBackOff ─────────────► конфиг 2.x на Tempo 3.0
│     («field ingester not found»): убрать легаси-блоки
└─ search пуст при живом пайплайне ────► ?tags= на Tempo 3.0 (нужен TraceQL q=)
      или ищете раньше, чем батчи доехали (подожди ~10с)
```

### Инцидент 1: трейсы пропали (экспорт в query-порт)

Полный разбор в `broken/scenario-01/`. Воспроизведение:

```bash
kubectl apply -f broken/scenario-01/collector-config-broken.yaml
kubectl -n lab rollout restart deploy/otel-collector
sleep 30
kubectl -n lab logs deploy/otel-collector --tail=10 | grep -o 'Exporting failed.*interval' | head -1
```

Реальный вывод (снят на нашем кластере) — gRPC-клиент упёрся в HTTP/1.1-сервер:

```
Exporting failed. Will retry the request after interval.
  "otelcol.component.id": "otlp/tempo", ...
  "error": "rpc error: code = Unavailable desc = connection error: desc =
    \"error reading server preface: http2: failed reading the frame payload:
      http2: frame too large, note that the frame header looked like an HTTP/1.1 header\""
```

> Текст ошибки сам подсказывает диагноз: exporter говорит gRPC (HTTP/2), а
> `tempo:3200` отвечает как HTTP/1.1 — это query API, не OTLP ingest.

Починка: `solutions/01-collector-endpoint/` (endpoint `:4317` + rollout restart).

---

## Проверка модуля

```bash
kubectl apply -k manifests/
bash verify/verify.sh
# [OK] tempo search: трейс найден (traceID=...)
# [OK] распределённый trace: спаны frontend И backend в одном traceID
# [OK] grafana datasources: tempo + loki(derivedFields) на месте
# [OK] module 30 verified
```

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Демонстрирует | req cpu/mem | lim cpu/mem |
|--------|-----|---------------|-------------|-------------|
| `tempo` | Deploy+Svc+CM | бэкенд трейсов, OTLP ingest vs query API | 100m/192Mi | 200m/384Mi |
| `otel-collector` | Deploy+Svc+CM | пайплайн receivers→processors→exporters | 50m/96Mi | 100m/192Mi |
| `backend` | Deploy+Svc+CM | автоинструментация + ручной спан | 50m/96Mi | 150m/192Mi |
| `frontend` | Deploy+Svc+CM | CLIENT-спан, проброс traceparent | 50m/96Mi | 150m/192Mi |
| `loadgen` | Deploy | постоянный трафик для Explore | 10m/16Mi | 20m/32Mi |
| `tempo-datasource` | Secret (monitoring) | provisioning Tempo + tracesToLogsV2 | — | — |
| `loki-datasource` | Secret (monitoring) | derivedFields + deleteDatasources | — | — |

Все Deployment'ы — `strategy: Recreate` (квота не вмещает surge), бюджет
рассчитан так, чтобы рядом со стеком 18 оставалось ~180m limits.cpu запаса
под telemetrygen-Job'ы.

---

## Теоретические вопросы (итоговые)

1. Три сигнала наблюдаемости и какой вопрос закрывает каждый?
2. Путь спана от `requests.get()` до строки в Grafana — перечисли все звенья.
3. Зачем коллектор, если Tempo принимает OTLP напрямую (минимум 3 причины)?
4. Как trace «склеивается» между сервисами и что в нём хранит каждый спан?
5. Почему «лог → трейс» требует и пакета instrumentation-logging, и regex в
   datasource, и фиксированных uid?

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-tempo-first-trace.md`** — Tempo + синтетический трейс + TraceQL.
2. **`tasks/02-collector-pipeline.md`** — коллектор в цепочке, debug exporter.
3. **`tasks/03-autoinstrument-app.md`** — автоинструментация, 4-спановый trace.
4. **`tasks/04-grafana-correlation.md`** — datasources, корреляция в обе стороны.

Дополнительно:
5. TraceQL: найди трейсы дольше 300ms (`{duration > 300ms}`) и трейсы с
   атрибутом `db.simulated.delay_ms > 250` (`{span.db.simulated.delay_ms > 250}`).
6. Сломай `OTEL_EXPORTER_OTLP_ENDPOINT` у frontend (укажи `:4318` при protocol
   grpc) и продиагностируй по логам приложения, а не коллектора.

---

## Шпаргалка

```bash
# === Tempo API (всё через TraceQL) ===
# поиск:   /api/search?q={resource.service.name="X"}   (urlencode!)
# трейс:   /api/traces/<traceID>
kubectl -n lab exec deploy/frontend -- wget -qO- \
  'http://tempo:3200/api/search?q=%7Bstatus%3Derror%7D&limit=5'

# === Коллектор ===
kubectl -n lab logs deploy/otel-collector --tail=30 | grep -E "Exporting failed|spans"
# конфиг применяется ТОЛЬКО рестартом:
kubectl apply -f manifests/otel-collector.yaml && kubectl -n lab rollout restart deploy/otel-collector

# === SDK (env приложения) ===
# OTEL_SERVICE_NAME, OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317,
# OTEL_TRACES_EXPORTER=otlp, OTEL_PYTHON_LOG_CORRELATION=true

# === Grafana ===
kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d
kubectl -n monitoring port-forward svc/kps-grafana 3909:80 &
# Explore → Tempo: {resource.service.name="frontend"}
# Explore → Loki:  {app="frontend"} |= "backend answered"
```

---

## Чему вы научились

- Читать trace как дерево спанов и понимать, кто и когда создаёт каждый спан
  (автоинструментация vs ручные).
- Собирать конвейер OTLP: SDK → Collector (receivers/processors/exporters) →
  Tempo, и диагностировать разрыв ЛЮБОГО звена по логам.
- Искать трейсы TraceQL'ем (по сервису, статусу, длительности, атрибутам).
- Связывать трейсы с логами в обе стороны через trace_id, derivedFields и
  tracesToLogsV2 — и обходить грабли provisioning'а (фиксированные uid,
  deleteDatasources).

---

## Уборка

```bash
kubectl delete -k manifests/ --ignore-not-found
kubectl -n lab delete job telemetrygen-direct telemetrygen-via-collector --ignore-not-found
# Вернуть исходный datasource Loki модуля 18 (наш v2 удалился вместе с manifests):
kubectl apply -f ../18-logs-tracing/manifests/datasource.yaml
```

> Развитие темы: метрики из спанов (Tempo metrics-generator + TraceQL metrics,
> GA в 3.0), tail-based sampling в коллекторе, OTel Operator с
> авто-инъекцией инструментации через аннотации подов.
