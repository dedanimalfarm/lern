# Лабораторная работа 18: Централизованное логирование — Loki, Promtail и LogQL

## Оглавление
<!-- TOC -->
- [Цели](#)
- [Предварительные требования](#-)
- [Развёртывание](#)
- [Часть 1: Архитектура — почему Loki «как Prometheus, только для логов»](#-1----loki--prometheus---)
  - [Теория для изучения перед частью](#----)
- [Часть 2: LogQL — выборка и line-фильтры](#-2-logql----line-)
  - [Теория для изучения перед частью](#----)
  - [2.1 Практика](#21-)
- [Часть 3: Парсеры — структура из строк на этапе запроса](#-3--------)
  - [Теория для изучения перед частью](#----)
  - [3.1 JSON-логи payment-api](#31-json--payment-api)
  - [3.2 pattern для текстовых логов](#32-pattern---)
  - [3.3 Грабля `__error__`](#33--__error__)
- [Часть 4: Метрики из логов](#-4---)
  - [Теория для изучения перед частью](#----)
  - [4.1 Практика (все числа — живые, со стенда)](#41-------)
- [Часть 5: Grafana — метрики и логи в одном расследовании](#-5-grafana-------)
- [Часть 6: Troubleshooting](#-6-troubleshooting)
- [Практические задания (отработка)](#--)
- [Проверка модуля](#-)
- [Шпаргалка LogQL](#-logql)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


⏱ время: 60–75 мин · 🎚 сложность: 3/5 · ⚙️ пререквизиты: модуль 08 (логи/события), модуль 17 (Prometheus/Grafana — для Части 5)

## Цели

1. Развернуть стек Loki + Promtail и понять его архитектуру (метки вместо полнотекстового индекса).
2. Освоить LogQL: селекторы потоков, line-фильтры, парсеры (`json`, `pattern`), `line_format`.
3. Строить МЕТРИКИ из логов: `rate`, `count_over_time`, `unwrap` + `quantile_over_time`.
4. Связать метрики и логи в Grafana в один workflow расследования.
5. Наступить на реальные грабли (CRI-префикс, `__error__`) и научиться их обходить.

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl get nodes   # 3 ноды Ready
```

## Развёртывание

```bash
kubectl apply -f manifests/
kubectl -n lab rollout status deploy/loki --timeout=120s
kubectl -n lab rollout status ds/promtail --timeout=120s
kubectl -n lab get pods
```

В `lab` появятся: Loki (сервер), Promtail (DaemonSet — по агенту на ноду) и два
генератора логов:

- `log-generator` — классические текстовые строки `<ts> LEVEL message id=N`;
- `payment-api` — структурированные JSON-логи `{"level":...,"status":...,"duration_ms":...}`.

Примеры реальных строк (снято со стенда):

```
2026-06-11T10:07:05+00:00 INFO user login id=9849
{"level":"error","status":500,"path":"/api/refund","duration_ms":163,"msg":"request handled"}
```

---

## Часть 1: Архитектура — почему Loki «как Prometheus, только для логов»

### Теория для изучения перед частью

```text
┌─────────────────┐       ┌─────────────┐       ┌─────────────────┐
│  Pod (app: A)   │       │             │       │   Grafana UI    │
│  stdout / logs  ├──────►│  Promtail   │       │ (LogQL queries) │
└─────────────────┘       │ (DaemonSet) │       └─────────┬───────┘
                          │             │                 │
┌─────────────────┐       │ - читает    │       ┌─────────▼───────┐
│  Pod (app: B)   ├──────►│   /var/log  ├──────►│   Loki Server   │
│  stdout / logs  │       │ - вешает    │ (HTTP)│  (index: labels │
└─────────────────┘       │   метки     │       │   data: chunks) │
                          └─────────────┘       └─────────────────┘
```

- **Поток (stream)** — уникальная комбинация меток (`{namespace, app, pod, container, ...}`).
  Это единица хранения: строки потока сжимаются в чанки.
- **Индексируются ТОЛЬКО метки** (как в Prometheus). Текст НЕ индексируется:
  полнотекстовый поиск — перебор (grep) внутри чанков, отобранных по меткам.
  Поэтому Loki на порядки дешевле ELK по RAM/диску, а скорость запроса зависит
  от того, насколько метки сузили перебор.
- **Кардинальность меток — главное табу.** Метка с уникальными значениями
  (`request_id`, `user_id`) создаёт миллионы потоков и убивает Loki так же,
  как кардинальность убивает Prometheus (модуль 17). Уникальные поля живут
  В ТЕЛЕ лога и достаются парсером на этапе ЗАПРОСА (Часть 3).

**Как строки попадают в Loki (наш конвейер):**

1. containerd пишет stdout контейнера в `/var/log/pods/<ns>_<pod>_<uid>/<container>/N.log`
   в **CRI-формате**: `<ts> <stdout|stderr> <F|P> <строка>`.
2. Promtail (через `kubernetes_sd`) находит поды своей ноды, через `relabel_configs`
   собирает путь `__path__` и метки, а `pipeline_stages: [cri: {}]` **отрезает
   CRI-префикс** — в Loki уезжает чистая строка приложения.
3. Push по HTTP в Loki; тот группирует по потокам и пишет чанки.

> ⚠️ **Грабля (наступили вживую):** без stage `cri` префикс `...Z stdout F `
> сохраняется В ТЕЛЕ лога — глазами это легко не заметить, но все парсеры
> Части 3 (`| json`, `| pattern`) ломаются: строка больше не начинается с `{`.
> См. комментарий в `manifests/promtail.yaml`.

**Контрольные вопросы:**
1. Чем индексация Loki принципиально отличается от Elasticsearch и что это даёт/стоит?
2. Почему `request_id` нельзя делать меткой, но можно искать по нему line-фильтром?
3. Из чего складывается путь, который Promtail тейлит на ноде?

---

## Часть 2: LogQL — выборка и line-фильтры

### Теория для изучения перед частью

Запрос LogQL = **селектор потоков** (по меткам, обязателен) + опциональный
конвейер обработки строк:

| Оператор | Смысл |
|----------|-------|
| `\|= "text"` | строка СОДЕРЖИТ подстроку |
| `!= "text"` | НЕ содержит |
| `\|~ "regex"` | матчится по regex (RE2; `(?i)` — без регистра) |
| `!~ "regex"` | не матчится |

Фильтры можно сцеплять — каждый сужает поток дальше.

### 2.1 Практика

Запросы выполняем прямо через API Loki (в Grafana Explore — те же выражения):

```bash
# хелпер: URL-encode запроса и запрос к Loki
lq() {
  local enc; enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1")
  kubectl -n lab exec deploy/loki -- wget -qO- \
    "http://localhost:3100/loki/api/v1/query_range?query=${enc}&limit=${2:-5}&since=5m"
}

# все логи приложения:
lq '{app="log-generator"}'

# только ошибки:
lq '{app="log-generator"} |= "ERROR"'
```

Реальный вывод (фрагмент `values`):

```
2026-06-11T10:09:18+00:00 ERROR gc finished id=3821
2026-06-11T10:09:35+00:00 ERROR payment queued id=4672
```

Сцепка фильтров: ошибки, но без upstream-шума и только про оплату:

```logql
{namespace="lab"} |= "ERROR" |~ "(?i)payment" != "queued"
```

**Контрольные вопросы:**
1. Почему `{app="..."}` обязателен, а `|= "ERROR"` — нет, и что будет со скоростью, если селектор слишком широкий?
2. Чем `|=` отличается от `|~` по стоимости выполнения?

---

## Часть 3: Парсеры — структура из строк на этапе запроса

### Теория для изучения перед частью

Парсер разбирает ТЕЛО строки и превращает поля в **временные метки запроса**
(не путать с метками потока — в хранилище ничего не добавляется):

| Парсер | Для чего |
|--------|----------|
| `\| json` | JSON-логи: каждое поле → метка (`status`, `duration_ms`, ...) |
| `\| logfmt` | пары `key=value` |
| `\| pattern "<a> <b>"` | быстрый разбор фиксированного текстового формата |
| `\| regexp "(?P<name>...)"` | произвольный формат (дороже pattern) |

После парсера работают **label-фильтры** (сравнения чисел и строк) и
`line_format` (переписать строку вывода через Go-шаблон).

### 3.1 JSON-логи payment-api

```bash
# только серверные ошибки:
lq '{app="payment-api"} | json | status >= 500'
```

Реальный вывод:

```
{"level":"error","status":500,"path":"/api/refund","duration_ms":163,"msg":"request handled"}
{"level":"error","status":500,"path":"/api/balance","duration_ms":251,"msg":"request handled"}
```

`line_format` делает выдачу человекочитаемой:

```bash
lq '{app="payment-api"} | json | status=500 | line_format "{{.path}} -> {{.status}} за {{.duration_ms}}мс"'
# /api/pay -> 500 за 364мс
# /api/refund -> 500 за 460мс
```

### 3.2 pattern для текстовых логов

```bash
lq '{app="log-generator"} | pattern "<ts> <level> <msg> id=<id>" | level="ERROR"'
# 2026-06-11T10:09:18+00:00 ERROR gc finished id=3821
```

### 3.3 Грабля `__error__`

Строки, которые парсер не осилил, получают метки `__error__`/`__error_details__`.
**Лог-запросы их МОЛЧА пропускают дальше, а метрик-запросы (Часть 4) падают
целиком с HTTP 400** (снято вживую):

```
pipeline error: 'JSONParserErr' ... Value looks like object, but can't find closing '}'
Use a label filter to intentionally skip this error. (e.g | __error__!="JSONParserErr").
```

Правило: в метрик-запросах после парсера всегда добавляйте `| __error__=""`.

**Контрольные вопросы:**
1. Чем метки парсера отличаются от меток потока (где живут, что стоят)?
2. Почему `| json` в дашборде может месяцами работать и внезапно сломаться одной строкой?

---

## Часть 4: Метрики из логов

### Теория для изучения перед частью

Поверх отфильтрованных потоков LogQL умеет агрегации НАД ЛОГАМИ:

- `rate({...}[5m])` — строк в секунду; `count_over_time` — строк за окно;
- `bytes_over_time` — байтов за окно (кто заливает хранилище);
- `unwrap <поле>` — взять ЧИСЛО из метки парсера и считать по нему:
  `quantile_over_time`, `avg_over_time`, `sum_over_time`, ...

Это «Prometheus по логам»: те же векторы, те же `sum by (...)`. Поверх таких
выражений строятся и алерты (Grafana Alerting или Loki Ruler).

### 4.1 Практика (все числа — живые, со стенда)

```bash
# мгновенные (instant) запросы — эндпоинт /query:
li() {
  local enc; enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1")
  kubectl -n lab exec deploy/loki -- wget -qO- "http://localhost:3100/loki/api/v1/query?query=${enc}"
}

# интенсивность по уровням (НЕ забываем __error__=""):
li 'sum by (level) (rate({app="payment-api"} | json | __error__="" [5m]))'
# {level="error"} => 0.16 строк/с
# {level="info"}  => 1.023 строк/с

# сколько ERROR-строк за 5 минут:
li 'sum(count_over_time({app="log-generator"} |= "ERROR" [5m]))'
# => 63

# p95 длительности запроса ПО ЛОГАМ, в разрезе path:
li 'quantile_over_time(0.95, {app="payment-api"} | json | __error__="" | unwrap duration_ms [5m]) by (path)'
# {path="/api/balance"} => 475.2
# {path="/api/pay"}     => 455.5
# {path="/api/refund"}  => 472.0

# кто сколько байт логов генерирует (планирование ёмкости):
li 'sum by (app) (bytes_over_time({namespace="lab"}[5m]))'
# log-generator => 39331   loki => 364407
# payment-api   => 45371   promtail => 182475
```

> 💡 Без `by (path)` результат `unwrap`-запроса группируется по ВСЕМ меткам
> потока+парсера (pod, filename, status, msg...) — получите кашу из серий.
> Явная группировка обязательна.

**Контрольные вопросы:**
1. Чем `rate` по логам отличается от `count_over_time` и когда что брать?
2. p95 по логам и p95 из histogram-метрики Prometheus (м17): плюсы/минусы каждого пути?
3. Как найти приложение, которое внезапно стало заливать Loki гигабайтами?

---

## Часть 5: Grafana — метрики и логи в одном расследовании

Loki подключается к Grafana автоматически: `manifests/datasource.yaml` создаёт
Secret `loki-datasource` с меткой `grafana_datasource: "1"` — sidecar Grafana
из модуля 17 его подхватывает.

```bash
kubectl -n monitoring port-forward svc/kps-grafana 3001:80 &
# пароль: kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

Workflow расследования «всплеск 500-х»:

1. **Explore → Loki**: `sum by (status) (rate({app="payment-api"} | json | __error__="" [1m]))` —
   видим аномалию по 500-м.
2. **Split view** (кнопка Split): слева метрика, справа логи
   `{app="payment-api"} | json | status=500` за тот же интервал — конкретные строки.
3. Дальше по строке: `pod`, `path`, `duration_ms` → виновник найден.

Обратная связка (из трейса/метрики в логи и наоборот) через **derived fields**
разобрана в модуле 30 (`loki-datasource-v2`: из строки лога с `trace_id` —
прыжок в Tempo). Здесь тот же механизм работает для любых полей.

---

## Часть 6: Troubleshooting

| Симптом | Причина | Диагностика / фикс |
|---------|---------|--------------------|
| В Loki ВООБЩЕ нет логов | Promtail не нашёл targets: нет `HOSTNAME=spec.nodeName` или `__path__` | `broken/scenario-01/`; `kubectl -n lab logs ds/promtail \| grep -i target` |
| `\| json` «не работает», метки пустые | CRI-префикс в теле строки (нет stage `cri`) | посмотреть сырую строку: `lq '{app=...}' 1`; добавить `pipeline_stages: [cri: {}]` |
| Метрик-запрос падает HTTP 400 `pipeline error` | строки с `__error__` в окне | добавить `\| __error__=""` после парсера |
| Запросы по `{namespace=...}` тормозят | селектор слишком широкий — перебор всех чанков ns | сузить метками (`app`, `container`), потом line-фильтры |
| Loki ест RAM/диск | кардинальность меток или болтливое приложение | `bytes_over_time by (app)`; убрать уникальные метки из pipeline |
| Половина старых строк «с мусорным префиксом» | строки записаны ДО включения `cri` | данные в чанках неизменяемы — ждать ретеншена или фильтровать `\|~ "^\\{"` |

---

## Практические задания (отработка)

1. Напишите запрос: все `WARN` строки `log-generator` за 10 минут, в которых
   `id` начинается на `9` (pattern-парсер + label-фильтр `|~`).
2. Постройте «топ путей по ошибкам»: `sum by (path) (count_over_time({app="payment-api"} | json | __error__="" | status=500 [10m]))`
   и проверьте сумму против `status>=400`.
3. Посчитайте среднюю (`avg_over_time` + `unwrap`) длительность запросов
   `/api/pay` и сравните с p95 — почему разрыв такой большой?
4. Сломайте парсинг сами: задеплойте под, который пишет невалидный JSON,
   и убедитесь, что лог-запрос его показывает, а метрик-запрос без
   `__error__=""` падает.
5. В Grafana соберите панель с двумя запросами: rate 500-х (Loki) и
   `container_cpu_usage_seconds_total` пода payment-api (Prometheus) — один
   дашборд, два датасорса.

---

## Проверка модуля

```bash
bash verify/verify.sh
# [OK] loki is ready
# [OK] логи доставляются: payment-api виден в Loki
# [OK] json-парсер работает: status>=500 находятся
# [OK] метрики из логов: rate() > 0
# [OK] module 18 verified
```

---

## Шпаргалка LogQL

```logql
{app="x"} |= "err" !~ "(?i)timeout"          # выборка + line-фильтры
{app="x"} | json | status >= 500             # парсер + label-фильтр
{app="x"} | pattern "<ts> <lvl> <msg>"       # текстовый формат
... | line_format "{{.path}} {{.status}}"    # переписать вывод
sum by (lvl) (rate({...} | json | __error__="" [5m]))     # строк/с
sum(count_over_time({...} |= "ERROR" [5m]))                # строк за окно
sum by (app) (bytes_over_time({namespace="lab"}[5m]))      # байты
quantile_over_time(0.95, {...} | unwrap dur [5m]) by (p)   # p95 из поля
```

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Роль |
|--------|-----|------|
| `loki` | Deployment / Service / ConfigMap | Сервер: index по меткам + чанки |
| `promtail` | DaemonSet / ConfigMap / RBAC | Агент на каждой ноде; `cri`-stage + relabel в `__path__` |
| `log-generator` | Deployment (busybox+awk) | Текстовые логи `<ts> LEVEL msg id=N` |
| `payment-api` | Deployment (busybox+awk) | JSON-логи: level/status/path/duration_ms |
| `loki-datasource` | Secret (`grafana_datasource: "1"`) | Автоподключение Loki к Grafana (м17) |

## Теоретические вопросы (итоговые)

1. Чем архитектура Loki принципиально отличается от Elasticsearch/OpenSearch с точки зрения индексации?
2. Почему Promtail — DaemonSet, а не Deployment, и какие hostPath ему нужны?
3. Что такое кардинальность меток и почему `request_id` — в тело лога, а не в метку?
4. Зачем нужен pipeline-stage `cri` и что сломается без него?
5. Почему лог-запрос терпит строки с `__error__`, а метрик-запрос — нет?
6. Когда метрику стоит считать из логов, а когда — инструментировать приложение (м17)?

## Чему вы научились

- Разворачивать Loki + Promtail и понимать путь строки от stdout до чанка.
- Писать LogQL: фильтры, парсеры (`json`/`pattern`), `line_format`, label-фильтры.
- Строить метрики из логов (`rate`, `count_over_time`, `unwrap`+квантили) и обходить `__error__`.
- Вести расследование «метрика ↔ логи» в Grafana Explore.

## Уборка

```bash
../../scripts/clean/clean-module.sh modules/18-centralized-logging
```
