# 05 · Observability — метрики (Prometheus + node_exporter + Grafana)

> Тема из вакансии: «Поднимать и поддерживать мониторинг и метрики (Prometheus / Grafana)».

⏱ **Время на выполнение:** ~1.5 часа
**Сложность:** 4/10

## Оглавление
- [Цель и навыки](#цель-и-навыки)
- [Теоретический минимум](#теоретический-минимум)
- [Базовая отработка](#базовая-отработка)
- [Расширенная отработка](#расширенная-отработка)
- [Проверка модуля](#проверка-модуля)
- [Контрольные вопросы](#контрольные-вопросы)
- [Troubleshooting — частые проблемы](#troubleshooting--частые-проблемы)
- [Уборка](#уборка)

## Цель и навыки

Поднять минимальный production-shape стек метрик и понять, что внутри. Не «накликать пэйнел», а **разобрать pull-модель Prometheus**, формат экспортёра, retention и базовый алертинг.

После лабы ты:

- объясняешь pull-модель и почему она удобнее push для метрик уровня инфраструктуры;
- читаешь формат `text/plain; version=0.0.4` (Prometheus exposition format) и пишешь экспортёр на 20 строк;
- настраиваешь `prometheus.yml` (scrape jobs, labels, relabeling);
- умеешь PromQL на уровне `rate`, `irate`, `histogram_quantile`, `sum by (…)`;
- знаешь, как Grafana подключает datasource и где живут дашборды;
- понимаешь, **что Prometheus — не для логов**, и почему дальше идёт лаба 06 с Loki.

## Теоретический минимум

**Prometheus** — TSDB + scraper. Раз в `scrape_interval` (по умолчанию 15s) дёргает HTTP-эндпоинт `/metrics` у каждой targets, парсит counters/gauges/histograms, кладёт в локальную TSDB (`tsdb/`). Retention — по времени (`--storage.tsdb.retention.time=15d`) или размеру.

**Exporters** — маленькие демоны, которые торчат `/metrics` для конкретной подсистемы:
- `node_exporter` — система (CPU, RAM, disk, NIC);
- `cAdvisor` — контейнеры;
- `blackbox_exporter` — пробы (HTTP/ICMP/TCP);
- свой экспортёр пишется на любом языке за 30 минут.

**PromQL** — язык запросов. Базовые конструкции:

```promql
node_cpu_seconds_total                                      # raw counter
rate(node_cpu_seconds_total[1m])                            # per-second
sum by (instance)(rate(node_cpu_seconds_total{mode!="idle"}[1m]))   # CPU usage
histogram_quantile(0.95, sum by (le)(rate(http_req_duration_seconds_bucket[5m])))  # p95 latency
```

**Grafana** — UI поверх datasource'ов (Prometheus, Loki, Postgres, etc.). Дашборд — JSON. В дев-режиме пользователь `admin/admin`, на prod — sso/oauth/oidc.

**На 1 GB RAM на t3.micro**: Prometheus + Grafana без проблем (Prom ≈150 MB, Grafana ≈120 MB), но **гаси compose-стек из предыдущих лаб** перед запуском, иначе словишь OOM.

## Базовая отработка

Все шаги — из домашнего каталога `~/lab05`.

### Шаг 1. compose-стек

```bash
mkdir -p ~/lab05/prom-data ~/lab05/grafana-data && cd ~/lab05
sudo chown 65534:65534 prom-data        # nobody:nogroup — UID контейнера prometheus
sudo chown 472:472 grafana-data         # UID контейнера grafana

cat > prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          host: 'junior-lab'

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
EOF

cat > compose.yml <<'EOF'
services:
  prometheus:
    image: prom/prometheus:v2.54.1
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=7d'
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prom-data:/prometheus
    ports: ["9090:9090"]
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:v1.8.2
    pid: host
    network_mode: host
    command:
      - '--path.rootfs=/host'
    volumes:
      - /:/host:ro,rslave
    restart: unless-stopped

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    privileged: true
    devices:
      - /dev/kmsg
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
    ports: ["8080:8080"]
    restart: unless-stopped

  grafana:
    image: grafana/grafana:11.2.0
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
      GF_USERS_ALLOW_SIGN_UP: 'false'
    volumes:
      - ./grafana-data:/var/lib/grafana
    ports: ["3000:3000"]
    restart: unless-stopped
EOF

docker compose up -d
docker compose ps
```

### Шаг 2. Проверить экспортёр и эндпоинты

```bash
curl -s http://127.0.0.1:9100/metrics | head -20         # node_exporter сырой
curl -s http://127.0.0.1:9090/-/healthy                  # Prometheus здоров
curl -s 'http://127.0.0.1:9090/api/v1/targets' | jq '.data.activeTargets[] | {scrape: .scrapePool, health, lastError}'
```

Все три цели должны быть `health: "up"`. Если `cadvisor` падает на t3.micro — это нормально для очень слабых VM, его можно убрать из compose.

### Шаг 3. PromQL руками

С локальной машины (или через ssh-туннель `ssh -L 9090:127.0.0.1:9090 ubuntu@<VM>`) открой http://localhost:9090 и попробуй:

```promql
up                                                  # 1 = up, 0 = down
rate(node_cpu_seconds_total{mode!="idle"}[1m])      # raw CPU
sum by (host) (rate(node_cpu_seconds_total{mode!="idle"}[1m]))  # CPU per host
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes     # free mem ratio
rate(node_network_receive_bytes_total{device="ens5"}[1m]) * 8   # bps in
```

### Шаг 4. Grafana

С локальной машины: `ssh -L 3000:127.0.0.1:3000 ubuntu@<VM>`. http://localhost:3000, логин `admin/admin`. Добавь datasource: URL `http://prometheus:9090` (это compose-DNS). Импортируй дашборд **Node Exporter Full** (ID `1860`) через Dashboards → Import.

## Расширенная отработка

### Задача 1. Свой экспортёр на 20 строк

```python
# ~/lab05/myexp.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import time, random
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404); self.end_headers(); return
        body = (
            "# HELP lab_random_value демонстрационная gauge\n"
            "# TYPE lab_random_value gauge\n"
            f"lab_random_value {random.random()}\n"
            "# HELP lab_uptime_seconds_total сколько живём\n"
            "# TYPE lab_uptime_seconds_total counter\n"
            f"lab_uptime_seconds_total {int(time.time()-start)}\n"
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.end_headers(); self.wfile.write(body)
start = time.time()
HTTPServer(("0.0.0.0", 9101), H).serve_forever()
```

Запусти `nohup python3 ~/lab05/myexp.py >/dev/null 2>&1 &`. Добавь scrape-job в `prometheus.yml`:

```yaml
  - job_name: 'myexp'
    static_configs:
      - targets: ['host.docker.internal:9101']     # либо IP хоста 172.17.0.1
```

> На docker-compose host.docker.internal по умолчанию нет, добавь `extra_hosts: ["host.docker.internal:host-gateway"]` сервису prometheus. Иначе пиши IP хоста.

После — `docker compose kill -s SIGHUP prometheus` (reload). Метрика `lab_random_value` появится в графане.

### Задача 2. Простой алерт через alertmanager

Подними `prom/alertmanager`, в `prometheus.yml` добавь `rule_files` и алерт «CPU > 80% 5 мин». Цель — увидеть алёрт в UI prometheus → Alerts. Не обязательно выводить наружу, важно понять механику `for: 5m`.

### Задача 3. Retention vs место

Сделай искусственный backfill (накачай данные за день), посмотри размер `prom-data`. Прикинь: при `retention 30d` сколько займёт TSDB? Это разговор про планирование диска.

## Проверка модуля

Вы можете запустить скрипт автоматической проверки, чтобы убедиться в корректности базовой настройки (поднятые контейнеры, доступность портов):
```bash
./verify.sh
```

## Контрольные вопросы

1. **Pull vs Push**: В чем фундаментальные отличия pull-модели Prometheus от push-моделей (например, StatsD/Graphite)? В каких редких случаях push всё-таки необходим и как Prometheus решает эту задачу?
2. **Типы метрик**: Чем `gauge` отличается от `counter`? Почему использование агрегатных функций (например, `sum` или `rate`) на `gauge` в большинстве случаев не имеет смысла? Почему `histogram` дороже в хранении, чем `summary`?
3. **Функции PromQL**: Зачем нужны функции `rate` и `irate`? Что произойдет с графиком счетчика (counter) при рестарте сервиса или экспортёра и как Prometheus обрабатывает этот сценарий?
4. **Архитектура и масштабирование**: Как развернуть High Availability (HA) Prometheus в продакшене? Если данных становится слишком много для одного узла, какие решения позволяют организовать долгосрочное хранение и горизонтальное масштабирование?

## Troubleshooting — частые проблемы

- **Grafana (472) permission denied**: Контейнер не может записать данные, так как директория `grafana-data` создана под root. **Лечение**: `sudo chown -R 472:472 ~/lab05/grafana-data`.
- **Prometheus (65534) permission denied**: Аналогичная проблема с директорией `prom-data`. **Лечение**: `sudo chown -R 65534:65534 ~/lab05/prom-data`.
- **node_exporter показывает 0 памяти/CPU**: Экспортер не примонтировал директории `/proc` или `/sys` хоста, из-за чего он смотрит на собственное окружение контейнера. **Лечение**: Используй `network_mode: host` и флаг `--path.rootfs=/host`.
- **Prometheus не видит свой экспортёр (myexp) на хосте**: Имя `host.docker.internal` не разрешается. **Лечение**: Добавь `extra_hosts: ["host.docker.internal:host-gateway"]` к сервису Prometheus в `compose.yml`.
- **OOM (Out Of Memory) или зависание после старта Grafana**: Вероятно, вы забыли погасить compose-стек из предыдущих лабораторных. На слабых виртуалках (1 GB RAM) это частая проблема. **Лечение**: Очистите ресурсы командой `docker compose -f ~/lab04/compose.yml down` и перезапустите текущий стек.

## Уборка

После завершения работы не забудьте удалить созданные ресурсы, чтобы они не мешали следующим модулям. Используйте предоставленный скрипт:

```bash
./cleanup.sh
```
