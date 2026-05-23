# 05 · Observability — метрики (Prometheus + node_exporter + Grafana)

> Тема из вакансии: «Поднимать и поддерживать мониторинг и метрики (Prometheus / Grafana)».

## Цель и навыки

Поднять минимальный production-shape стек метрик и понять, что внутри. Не «накликать пэйнел», а **разобрать pull-модель Prometheus**, формат экспортёра, retention и базовый алертинг.

После лабы ты:

- объясняешь pull-модель и почему она удобнее push для метрик уровня инфраструктуры;
- читаешь формат `text/plain; version=0.0.4` (Prometheus exposition format) и пишешь экспортёр на 20 строк;
- настраиваешь `prometheus.yml` (scrape jobs, labels, relabeling);
- умеешь PromQL на уровне `rate`, `irate`, `histogram_quantile`, `sum by (…)`;
- знаешь, как Grafana подключает datasource и где живут дашборды;
- понимаешь, **что Prometheus — не для логов**, и почему дальше идёт [06](../06-observability-logs/) с Loki.

## Теоретический минимум

**Prometheus** — TSDB + scraper. Раз в `scrape_interval` (по умолчанию 15s) дёргает HTTP-эндпоинт `/metrics` у каждой targets, парсит counters/gauges/histograms, кладёт в локальную TSDB (`tsdb/`). Retention — по времени (`--storage.tsdb.retention.time=15d`) или размеру.

**Exporters** — маленькие демоны, которые торчат `/metrics` для конкретной подсистемы:
- `node_exporter` — система (CPU, RAM, disk, NIC);
- `cAdvisor` — контейнеры;
- `blackbox_exporter` — пробы (HTTP/ICMP/TCP);
- свой экспортёр пишется на любом языке за 30 минут.

**PromQL** — язык запросов. Базовые конструкции:

```
node_cpu_seconds_total                                      # raw counter
rate(node_cpu_seconds_total[1m])                            # per-second
sum by (instance)(rate(node_cpu_seconds_total{mode!="idle"}[1m]))   # CPU usage
histogram_quantile(0.95, sum by (le)(rate(http_req_duration_seconds_bucket[5m])))  # p95 latency
```

**Grafana** — UI поверх datasource'ов (Prometheus, Loki, Postgres, etc.). Дашборд — JSON. В дев-режиме пользователь `admin/admin`, на prod — sso/oauth/oidc.

**На 1 GB RAM на t3.micro**: Prometheus + Grafana без проблем (Prom ≈150 MB, Grafana ≈120 MB), но **гаси compose-стек из [04](../04-virtualization/)** перед запуском, иначе словишь OOM.

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

```
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

## Acceptance criteria

- [ ] `docker compose ps` показывает `prometheus`, `node-exporter`, `grafana` running.
- [ ] `curl :9090/api/v1/targets` — все targets `up`.
- [ ] В Grafana импортирован дашборд 1860, графики ненулевые.
- [ ] (Расширенная) собственный `myexp` виден в targets и метрика `lab_random_value` запрашивается в Prom UI.

## Что обсудить на ревью

1. Pull vs push — где push реально нужен? (Подсказка: batch-jobs → Pushgateway.)
2. Зачем `rate` против `irate`? Что произойдёт на счётчике при рестарте сервиса?
3. Чем gauge отличается от counter и почему histogram дороже summary?
4. Как ты бы развернул HA-Prometheus на проде? (Подсказка: Thanos / Cortex / Mimir / Victoria.)
5. Где у тебя секреты в этом стенде (Grafana admin password) и почему сейчас они в env-vars compose'а — плохо? — переход к [`07-secrets-vault`](../07-secrets-vault/).

## Как погасить (важно на t3.micro)

```bash
cd ~/lab05 && docker compose down            # контейнеры стопают
docker volume ls                              # данные в bind-mount'е, volume'ов нет
# Полная зачистка:
rm -rf ~/lab05/{prom-data,grafana-data}
```

## Грабли

| Симптом | Причина | Лечение |
|---------|---------|---------|
| Grafana 472 permission denied | bind-mount без chown 472:472 | `sudo chown -R 472:472 grafana-data` |
| Prometheus падает с `permission denied` на /prometheus | bind-mount без chown 65534 | `sudo chown -R 65534:65534 prom-data` |
| node_exporter показывает 0 памяти/CPU | не примонтировал `/proc` или `/sys` | используй `network_mode: host` и `--path.rootfs=/host` |
| Prometheus не видит свой экспортёр на хосте | DNS `host.docker.internal` не настроен | `extra_hosts: ["host.docker.internal:host-gateway"]` |
| OOM после старта Grafana | не погасил compose из лабы 04 | `docker compose -f ~/lab04/compose.yml down` |
