# 06 · Observability — логи (Loki + Promtail)

> Тема из вакансии: «Логирование (Loki / OpenSearch)».

## Цель и навыки

Поднять стек логирования, понять модель Loki («индексируем **только метки**, тело логов — в чанках») и связать его с уже работающей Grafana из [05](../05-observability-metrics/).

После лабы ты:

- знаешь, чем Loki концептуально отличается от OpenSearch/ELK (label-индекс vs full-text);
- умеешь настраивать **Promtail** на сбор `journald` и файлов с правильными labels;
- пишешь LogQL: `{job="systemd"} |= "error"`, `rate({...}[5m])`, `unwrap` для метрик из логов;
- подключаешь Loki как datasource в Grafana и строишь lookup'ы;
- понимаешь, что такое «high cardinality labels» и почему `request_id` нельзя класть в label.

## Теоретический минимум

**Loki** хранит логи как поток (stream) с фиксированным набором labels плюс «тело». Индексирует **только labels** (а не содержимое). За счёт этого — дёшево, быстро на стримах, плохо на «найди слово в 30 ТБ за всё время».

**Promtail / Grafana Alloy / Vector / Fluent Bit** — агенты-сборщики. Читают журнал/файл, парсят, добавляют labels, отправляют в Loki. В этой лабе — **Promtail** (классика), но в проде сейчас рекомендуют `grafana/alloy`.

**LogQL** — двойник PromQL для логов:

```
{job="systemd"}                                      # все строки этого стрима
{job="systemd"} |= "error"                            # с подстрокой
{job="systemd"} | json | level="error"               # парсинг JSON в поле
sum by (unit) (rate({job="systemd"}[5m]))            # метрики из логов
```

**Высокая cardinality labels = смерть Loki.** Не клади в labels: user_id, request_id, IP, trace_id. Они должны быть в **теле** строки и доставаться через парсер. В labels — низкокардинальные: job, host, env, namespace, pod, service.

## Базовая отработка

### Шаг 1. Добавить Loki и Promtail в compose из лабы 05

```bash
cd ~/lab05
sudo mkdir -p loki-data && sudo chown 10001:10001 loki-data    # UID loki

cat > loki-config.yml <<'EOF'
auth_enabled: false
server:
  http_listen_port: 3100
ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore: { store: inmemory }
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  max_chunk_age: 1h
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index: { prefix: index_, period: 24h }
storage_config:
  filesystem: { directory: /loki/chunks }
  tsdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/cache
limits_config:
  retention_period: 168h
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  allow_structured_metadata: false
compactor:
  working_directory: /loki/compactor
  delete_request_store: filesystem
EOF

cat > promtail-config.yml <<'EOF'
server:
  http_listen_port: 9080
positions:
  filename: /tmp/positions.yaml
clients:
  - url: http://loki:3100/loki/api/v1/push
scrape_configs:
  - job_name: journal
    journal:
      max_age: 12h
      path: /var/log/journal
      labels:
        job: systemd
        host: junior-lab
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: unit
      - source_labels: ['__journal_priority_keyword']
        target_label: priority
  - job_name: varlogs
    static_configs:
      - targets: [localhost]
        labels:
          job: varlogs
          host: junior-lab
          __path__: /var/log/*.log
EOF
```

Допиши в `compose.yml` сервисы:

```yaml
  loki:
    image: grafana/loki:3.1.1
    command: ["-config.file=/etc/loki/config.yml"]
    volumes:
      - ./loki-config.yml:/etc/loki/config.yml:ro
      - ./loki-data:/loki
    ports: ["3100:3100"]
    restart: unless-stopped

  promtail:
    image: grafana/promtail:3.1.1
    command: ["-config.file=/etc/promtail/config.yml"]
    volumes:
      - ./promtail-config.yml:/etc/promtail/config.yml:ro
      - /var/log:/var/log:ro
      - /var/log/journal:/var/log/journal:ro
      - /etc/machine-id:/etc/machine-id:ro
    restart: unless-stopped
```

Подними и проверь:

```bash
docker compose up -d loki promtail
curl -s http://127.0.0.1:3100/ready
curl -s 'http://127.0.0.1:3100/loki/api/v1/labels' | jq
curl -s -G 'http://127.0.0.1:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="systemd"}' \
  --data-urlencode "start=$(date -d '5 min ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" | jq '.data.result | length'
```

Если последняя команда вернула > 0 — Loki принимает логи из journald.

### Шаг 2. Подключить Loki в Grafana

В Grafana → Connections → Data sources → Add → Loki. URL: `http://loki:3100`. **Save & test**.

Explore → datasource Loki → запрос:

```
{job="systemd"}
{job="systemd", unit="ssh.service"}
{job="systemd"} |= "Accepted publickey"     # видишь свои SSH-логины
```

### Шаг 3. Сгенерировать «инцидент» и найти в логах

```bash
# в одной сессии
for i in {1..50}; do logger -t labapp -p user.error "FAKE_ERROR id=$i path=/api/x"; sleep 0.2; done
```

В Loki:

```
{job="systemd"} |= "FAKE_ERROR" | regexp "id=(?P<id>\\d+)" | json="false"
```

## Расширенная отработка

### Задача 1. Метрики из логов

Открой Grafana → Explore. Построй график числа ошибок в минуту:

```
sum by (unit) (rate({job="systemd"} |~ "(?i)error|fail" [1m]))
```

Это **PromQL поверх Loki** — мощный шаблон «без отдельного экспортёра считаем ошибки».

### Задача 2. Парсинг JSON-логов

Запусти контейнер, который пишет JSON:

```bash
docker run -d --name jsonlogs --log-driver=json-file --log-opt max-size=10m \
  alpine sh -c 'while true; do echo "{\"level\":\"info\",\"msg\":\"tick\",\"t\":$(date +%s)}"; sleep 2; done'
```

В promtail-config добавь скрейп `/var/lib/docker/containers/*/*-json.log` с `pipeline_stages: [{ json: { expressions: { level: level, msg: msg } } }, { labels: { level: '' } }]`. Перезапусти promtail. В Loki:

```
{job="docker"} | json | level="info"
```

### Задача 3. Retention и compactor

Проверь `loki-data/`: видишь `index/`, `chunks/`, `compactor/`. Поменяй retention на 24 часа, перезапусти, посмотри размер. Это — практический разговор про «логи дёшевы, пока retention короткий».

## Acceptance criteria

- [ ] `curl :3100/ready` → ok.
- [ ] В Grafana → Explore запрос `{job="systemd"}` показывает живой стрим.
- [ ] Запрос с `|= "Accepted publickey"` находит твои SSH-логины.
- [ ] (Расширенная) график `rate(...)` показывает ненулевое число «error» за минуту после генератора.

## Что обсудить на ревью

1. Почему **request_id** нельзя класть в Loki labels?
2. Чем Loki хуже OpenSearch для поиска «слова за полгода»? Чем лучше для tail'инга стримов?
3. Что делает `compactor` и почему без него Loki замусоривает диск?
4. Какой агент собирать предпочтительнее в 2026 — Promtail, Vector, Alloy, Fluent Bit? (Подсказка: Grafana движет всех на Alloy.)
5. Как ты бы доставлял логи из 100 нод в Loki надёжно (потеря connectivity, переполнение)? — буфер на диске агента, ack-семантика.

## Как погасить

```bash
cd ~/lab05 && docker compose down
sudo rm -rf loki-data
```

## Грабли

| Симптом | Причина | Лечение |
|---------|---------|---------|
| `permission denied` на `loki-data` | UID несовпадение | `sudo chown -R 10001:10001 loki-data` |
| `failed to ingest, tenant is at max series limit` | сильно высокая cardinality | убери `instance_id`/`request_id` из labels |
| Promtail не видит journald | нет `/etc/machine-id` в контейнере | пробрось `:ro` |
| `error parsing config: schema_config: ...` | поменял схему задним числом | `from:` должен быть в **будущем** или совпадать с моментом запуска |
| Логи приходят с задержкой | мелкие `chunk_idle_period`/`max_chunk_age` | для лабы — поставь 5m/1h; на проде — баланс |
