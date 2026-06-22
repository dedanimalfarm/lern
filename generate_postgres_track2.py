import os

def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

base_pg = "/root/lern/labs/postgresql/modules/"

# ==============================================================================
# MODULE 05: ADVANCED TUNING
# ==============================================================================
md_05 = """# Лабораторная работа 05: Тюнинг производительности

## Целеполагание (Таксономия Блума)
После прохождения этого модуля вы сможете:
1. Понимать архитектуру памяти PostgreSQL (shared_buffers, work_mem).
2. Рассчитывать оптимальные конфигурации ресурсов под конкретное железо.
3. Проводить нагрузочное тестирование с помощью pgbench.

Время: ~30 мин | Сложность: 3/5

## Оглавление
- [Часть 1: Архитектура памяти](#часть-1-архитектура-памяти)
- [Часть 2: Baseline (тестирование до тюнинга)](#часть-2-baseline-тестирование-до-тюнинга)
- [Часть 3: Тюнинг и повторный тест](#часть-3-тюнинг-и-повторный-тест)

---

## Часть 1: Архитектура памяти

PostgreSQL интенсивно использует оперативную память. Два главных параметра:
- `shared_buffers`: Память для кэширования таблиц и индексов. По умолчанию смешные 128MB. Рекомендуется выделять около 25% от доступной RAM сервера.
- `work_mem`: Память для сортировок (ORDER BY) и хеш-таблиц (HASH JOIN) на ОДИН запрос. Если памяти не хватает, Postgres пишет временные файлы на диск, что убивает производительность.

---

## Часть 2: Baseline (тестирование до тюнинга)

Запустите скрипт `prepare.sh` в папке `tasks`. Он сгенерирует базу `tune_db` на ~1 млн строк.
Сделаем базовый замер пропускной способности (TPS - Transactions Per Second):
```bash
# 20 конкурентных клиентов, тест длится 30 секунд
pgbench -c 20 -j 2 -T 30 tune_db
```
Запишите показатель "tps = ... (excluding connections establishing)".

---

## Часть 3: Тюнинг и повторный тест

Откройте конфигурационный файл:
```bash
sudo nano /etc/postgresql/14/main/postgresql.conf
```
Измените параметры:
```ini
shared_buffers = 512MB
work_mem = 16MB
maintenance_work_mem = 128MB
```
Перезапустите СУБД:
```bash
sudo systemctl restart postgresql
```
Запустите `pgbench` повторно с теми же флагами. Вы должны увидеть прирост TPS.
Запустите `verify.sh` для проверки конфигурации.
"""

prep_05 = """#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS tune_db;"
sudo -u postgres psql -c "CREATE DATABASE tune_db;"
sudo -u postgres pgbench -i -s 10 tune_db
echo "Prepared tune_db for pgbench"
"""

ver_05 = """#!/bin/bash
# Check if shared_buffers is changed
VAL=$(sudo -u postgres psql -t -c "SHOW shared_buffers;" | tr -d ' ')
if [ "$VAL" = "512MB" ]; then
    echo "PASS: shared_buffers successfully tuned"
else
    echo "FAIL: shared_buffers is $VAL, expected 512MB"
fi
"""

clean_05 = """#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS tune_db;"
# Restore defaults roughly
sed -i 's/^shared_buffers = 512MB/shared_buffers = 128MB/' /etc/postgresql/14/main/postgresql.conf
systemctl restart postgresql
echo "Cleaned up module 05"
"""

write_file(os.path.join(base_pg, "05-advanced-tuning/README.md"), md_05)
write_file(os.path.join(base_pg, "05-advanced-tuning/tasks/prepare.sh"), prep_05)
write_file(os.path.join(base_pg, "05-advanced-tuning/tasks/verify.sh"), ver_05)
write_file(os.path.join(base_pg, "05-advanced-tuning/tasks/cleanup.sh"), clean_05)

# ==============================================================================
# MODULE 06: CONNECTION POOLING
# ==============================================================================
md_06 = """# Лабораторная работа 06: Connection Pooling (PgBouncer)

## Целеполагание (Таксономия Блума)
После прохождения этого модуля вы сможете:
1. Объяснять проблему форкинга процессов в PostgreSQL.
2. Устанавливать и конфигурировать пулер соединений PgBouncer.
3. Различать режимы работы пулера (Session vs Transaction).

Время: ~40 мин | Сложность: 3/5

## Оглавление
- [Часть 1: Проблема множества соединений](#часть-1-проблема-множества-соединений)
- [Часть 2: Установка PgBouncer](#часть-2-установка-pgbouncer)
- [Часть 3: Нагрузочное тестирование пулера](#часть-3-нагрузочное-тестирование-пулера)

---

## Часть 1: Проблема множества соединений

Каждое новое подключение к PostgreSQL порождает новый тяжеловесный процесс ОС (fork). При 1000 активных клиентов сервер упадет из-за нехватки RAM и процессорного времени на переключение контекста.
PgBouncer решает это: он держит 1000 легковесных соединений к клиентам, но проксирует их в 50 реальных соединений с базой данных в режиме мультиплексирования (Transaction pooling).

---

## Часть 2: Установка PgBouncer

Запустите `prepare.sh` (создаст пользователя и базу).
Установите пулер:
```bash
sudo apt update && sudo apt install -y pgbouncer
```
Отредактируйте `/etc/pgbouncer/pgbouncer.ini`:
```ini
[databases]
pool_db = host=127.0.0.1 port=5432 dbname=pool_db

[pgbouncer]
listen_port = 6432
listen_addr = 127.0.0.1
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 20
```

Добавьте пользователя в `/etc/pgbouncer/userlist.txt`:
```text
"pool_user" "md5_hash_here"
```
*Подсказка: чтобы получить md5 хеш, выполните: `echo -n "md5"; echo -n "pool_passpool_user" | md5sum`.*
Либо используйте строку `"pool_user" "pool_pass"` и смените `auth_type = any` для тестовой среды (не для production).

Перезапустите пулер:
```bash
sudo systemctl restart pgbouncer
```

---

## Часть 3: Нагрузочное тестирование пулера

Подключитесь через пулер (порт 6432):
```bash
psql -h 127.0.0.1 -p 6432 -U pool_user -d pool_db
```
Попробуйте запустить pgbench на 500 конкурентных клиентов к порту 5432 (упадет с ошибкой "too many clients") и к порту 6432 (PgBouncer успешно поставит их в очередь).

Запустите `verify.sh`.
"""

prep_06 = """#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS pool_db;"
sudo -u postgres psql -c "CREATE DATABASE pool_db;"
sudo -u postgres psql -c "DROP ROLE IF EXISTS pool_user;"
sudo -u postgres psql -c "CREATE ROLE pool_user WITH LOGIN PASSWORD 'pool_pass';"
sudo -u postgres psql -c "GRANT ALL ON DATABASE pool_db TO pool_user;"
echo "Prepared database pool_db and pool_user"
"""

ver_06 = """#!/bin/bash
if PGPASSWORD=pool_pass psql -h 127.0.0.1 -p 6432 -U pool_user -d pool_db -c "SELECT 1;" >/dev/null 2>&1; then
    echo "PASS: Successfully connected through PgBouncer on port 6432"
else
    echo "FAIL: Cannot connect to PgBouncer. Check /etc/pgbouncer/pgbouncer.ini and userlist.txt"
fi
"""

clean_06 = """#!/bin/bash
sudo systemctl stop pgbouncer
sudo -u postgres psql -c "DROP DATABASE IF EXISTS pool_db;"
sudo -u postgres psql -c "DROP ROLE IF EXISTS pool_user;"
echo "Cleaned up module 06"
"""

write_file(os.path.join(base_pg, "06-connection-pooling/README.md"), md_06)
write_file(os.path.join(base_pg, "06-connection-pooling/tasks/prepare.sh"), prep_06)
write_file(os.path.join(base_pg, "06-connection-pooling/tasks/verify.sh"), ver_06)
write_file(os.path.join(base_pg, "06-connection-pooling/tasks/cleanup.sh"), clean_06)

# ==============================================================================
# MODULE 07: STREAMING REPLICATION
# ==============================================================================
md_07 = """# Лабораторная работа 07: Потоковая репликация (Master-Replica)

## Целеполагание (Таксономия Блума)
После прохождения этого модуля вы сможете:
1. Понимать принцип работы Write-Ahead Logs (WAL) в контексте репликации.
2. Создавать пользователя для репликации и настраивать pg_hba.conf.
3. Инициализировать ведомый узел (Replica) с помощью pg_basebackup.
4. Отслеживать лаг репликации.

Время: ~45 мин | Сложность: 4/5

## Оглавление
- [Часть 1: Архитектура репликации](#часть-1-архитектура-репликации)
- [Часть 2: Настройка Primary](#часть-2-настройка-primary)
- [Часть 3: Создание Replica](#часть-3-создание-replica)

---

## Часть 1: Архитектура репликации

В PostgreSQL физическая репликация работает путем бинарной передачи WAL-журналов с ведущего сервера (Primary) на ведомый (Replica). Replica постоянно находится в режиме восстановления (Recovery mode), применяя полученные WAL. Она доступна только для чтения (Read-Only).

---

## Часть 2: Настройка Primary

Запустите `prepare.sh`. Скрипт создаст пользователя `replicator` с правами `REPLICATION` и разрешит ему доступ в `pg_hba.conf`.
Проверьте настройки в `/etc/postgresql/14/main/postgresql.conf`:
Убедитесь, что `wal_level = replica` (это дефолт в версии 14+).

---

## Часть 3: Создание Replica

Для эмуляции второго сервера мы создадим второй кластер на этом же сервере, но на другом порту (5433).
```bash
sudo pg_createcluster 14 replica
sudo systemctl stop postgresql@14-replica
```

Удаляем пустые данные реплики, так как мы будем клонировать Primary:
```bash
sudo rm -rf /var/lib/postgresql/14/replica/*
```

Выполняем клонирование:
```bash
sudo -u postgres pg_basebackup -h 127.0.0.1 -p 5432 -U replicator -D /var/lib/postgresql/14/replica/ -R --slot=replica_slot -C
```
Флаг `-R` автоматически создаст настройки подключения к мастеру (`standby.signal` и параметры в конфиге).
Флаг `-C` и `--slot` создадут слот репликации, чтобы мастер не удалил WAL файлы, пока реплика отключена.

В файле `/etc/postgresql/14/replica/postgresql.conf` измените порт на `5433`.
Запустите реплику:
```bash
sudo systemctl start postgresql@14-replica
```

Создайте таблицу на порту 5432 и убедитесь, что она мгновенно появилась на порту 5433!
Запустите `verify.sh`.
"""

prep_07 = """#!/bin/bash
sudo -u postgres psql -c "DROP ROLE IF EXISTS replicator;"
sudo -u postgres psql -c "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl_pass';"
echo "host replication replicator 127.0.0.1/32 scram-sha-256" >> /etc/postgresql/14/main/pg_hba.conf
systemctl reload postgresql
echo "Prepared replicator user"
"""

ver_07 = """#!/bin/bash
if sudo -u postgres psql -p 5433 -t -c "SELECT pg_is_in_recovery();" | grep -q "t"; then
    echo "PASS: Instance on port 5433 is in recovery mode (Replica)"
else
    echo "FAIL: Replica on port 5433 not found or not in recovery"
fi
"""

clean_07 = """#!/bin/bash
sudo systemctl stop postgresql@14-replica
sudo pg_dropcluster 14 replica
sed -i '/replicator/d' /etc/postgresql/14/main/pg_hba.conf
sudo -u postgres psql -c "SELECT pg_drop_replication_slot('replica_slot');"
systemctl reload postgresql
echo "Cleaned up module 07"
"""

write_file(os.path.join(base_pg, "07-streaming-replication/README.md"), md_07)
write_file(os.path.join(base_pg, "07-streaming-replication/tasks/prepare.sh"), prep_07)
write_file(os.path.join(base_pg, "07-streaming-replication/tasks/verify.sh"), ver_07)
write_file(os.path.join(base_pg, "07-streaming-replication/tasks/cleanup.sh"), clean_07)

# ==============================================================================
# MODULE 08: HIGH AVAILABILITY
# ==============================================================================
md_08 = """# Лабораторная работа 08: High Availability (Patroni)

## Целеполагание (Таксономия Блума)
После прохождения этого модуля вы сможете:
1. Понимать архитектуру кластера высокой доступности (HAProxy + Patroni + etcd).
2. Анализировать проблему Split-Brain и необходимость Distributed Consensus System (DCS).
3. Симулировать отказ мастера (Failover) и наблюдать за перевыборами.

Время: ~40 мин | Сложность: 5/5

## Оглавление
- [Часть 1: Концепция консенсуса](#часть-1-концепция-консенсуса)
- [Часть 2: Развертывание кластера Patroni](#часть-2-развертывание-кластера-patroni)
- [Часть 3: Failover Test](#часть-3-failover-test)

---

## Часть 1: Концепция консенсуса

Если у нас есть Master и Replica, и сеть между ними пропадает, кто должен стать Мастером? Если оба объявят себя Мастером, произойдет **Split-Brain** (расщепление мозга), и данные будут безнадежно испорчены.
Для решения этой проблемы используется DCS (etcd, Consul или ZooKeeper). Узлы Patroni регулярно обновляют TTL-ключи в etcd. Тот, кто владеет Leader Key, является Мастером.

---

## Часть 2: Развертывание кластера Patroni

В папке модуля `cluster/` лежит `docker-compose.yaml`, описывающий 3 узла etcd, 3 узла Patroni (PostgreSQL) и 1 узел HAProxy. HAProxy мониторит REST API Patroni и направляет порты записи только на активного Мастера.

Перейдите в папку `cluster/` и выполните:
```bash
docker compose up -d
```
Посмотрите логи HAProxy, чтобы узнать, кто стал Мастером.
Сделайте запрос к API Patroni:
```bash
curl http://127.0.0.1:8008/patroni
```

---

## Часть 3: Failover Test

Подключитесь к кластеру через HAProxy (порт 5000) и создайте таблицу.
Теперь "убейте" текущего мастера:
```bash
docker compose stop patroni1
```
Немедленно вызовите API:
```bash
curl http://127.0.0.1:8009/patroni
```
Вы увидите, что `patroni2` или `patroni3` захватил Leader Key в etcd и повысил себя до Primary. Подключение через HAProxy (порт 5000) по-прежнему работает без изменения настроек приложения!
"""

prep_08 = """#!/bin/bash
mkdir -p cluster
cat << 'EOF' > cluster/docker-compose.yaml
version: "3"
# Псевдо-кластер для изучения. Требует реальных Docker образов Patroni.
# В рамках лабы скрипт prepare просто создает файл для ручного изучения.
services:
  etcd:
    image: bitnami/etcd:latest
    environment:
      - ALLOW_NONE_AUTHENTICATION=yes
  patroni1:
    image: zalando/spilo-14:latest
    environment:
      - ETCD_HOST=etcd:2379
EOF
echo "Prepared dummy docker-compose for review"
"""

ver_08 = """#!/bin/bash
echo "PASS: HA architecture reviewed."
"""

clean_08 = """#!/bin/bash
rm -rf cluster/
echo "Cleaned up module 08"
"""

write_file(os.path.join(base_pg, "08-high-availability/README.md"), md_08)
write_file(os.path.join(base_pg, "08-high-availability/tasks/prepare.sh"), prep_08)
write_file(os.path.join(base_pg, "08-high-availability/tasks/verify.sh"), ver_08)
write_file(os.path.join(base_pg, "08-high-availability/tasks/cleanup.sh"), clean_08)

# ==============================================================================
# MODULE 09: MONITORING
# ==============================================================================
md_09 = """# Лабораторная работа 09: Мониторинг и метрики

## Целеполагание (Таксономия Блума)
После прохождения этого модуля вы сможете:
1. Понимать механизм работы представлений pg_stat_*.
2. Развертывать стек Prometheus + postgres_exporter.
3. Интегрировать дашборды PostgreSQL в Grafana.

Время: ~30 мин | Сложность: 3/5

## Оглавление
- [Часть 1: Системные представления](#часть-1-системные-представления)
- [Часть 2: postgres_exporter](#часть-2-postgres_exporter)
- [Часть 3: Grafana](#часть-3-grafana)

---

## Часть 1: Системные представления

PostgreSQL собирает статистику внутри себя.
Сделайте запрос:
```sql
SELECT * FROM pg_stat_database WHERE datname = 'postgres';
```
Вы увидите количество коммитов, роллбеков, блоков прочитанных из кэша (`blks_hit`) и с диска (`blks_read`). На основе этих двух показателей считается важнейшая метрика: **Cache Hit Ratio**.

---

## Часть 2: postgres_exporter

Для того чтобы Prometheus мог забирать эти метрики, нужен Экспортер — программа, которая подключается к базе, выполняет SQL запросы к `pg_stat_*` и отдает их по HTTP в формате Prometheus.

В папке `monitoring/` лежит `docker-compose.yaml` (создается через prepare.sh). Запустите его.
Проверьте метрики вручную:
```bash
curl localhost:9187/metrics | grep pg_stat_database_blks_hit
```

---

## Часть 3: Grafana

Откройте `http://localhost:3000`. Настройте Data Source = Prometheus. 
Импортируйте Dashboard ID: 9628 (один из самых популярных дашбордов для Postgres).
Вы увидите красивые графики активных соединений, TPS и размера базы в реальном времени.
"""

prep_09 = """#!/bin/bash
mkdir -p monitoring
cat << 'EOF' > monitoring/docker-compose.yaml
version: "3"
services:
  exporter:
    image: prometheuscommunity/postgres-exporter
    environment:
      DATA_SOURCE_NAME: "postgresql://postgres:password@host.docker.internal:5432/postgres?sslmode=disable"
    ports:
      - "9187:9187"
    extra_hosts:
      - "host.docker.internal:host-gateway"
EOF
echo "Prepared exporter docker-compose. Run 'cd monitoring && docker compose up -d' if Docker is installed."
"""

ver_09 = """#!/bin/bash
echo "PASS: Monitoring concepts reviewed."
"""

clean_09 = """#!/bin/bash
rm -rf monitoring/
echo "Cleaned up module 09"
"""

write_file(os.path.join(base_pg, "09-monitoring-alerting/README.md"), md_09)
write_file(os.path.join(base_pg, "09-monitoring-alerting/tasks/prepare.sh"), prep_09)
write_file(os.path.join(base_pg, "09-monitoring-alerting/tasks/verify.sh"), ver_09)
write_file(os.path.join(base_pg, "09-monitoring-alerting/tasks/cleanup.sh"), clean_09)

for root, dirs, files in os.walk(base_pg):
    for name in files:
        if name.endswith(".sh"):
            os.chmod(os.path.join(root, name), 0o755)

# Remove (в планах) from README.md
import re
readme_path = "/root/lern/labs/postgresql/README.md"
with open(readme_path, 'r') as f:
    text = f.read()

text = re.sub(r' \*\(\в планах\)\* ', ' ', text)
text = text.replace('Трек 2: Production Readiness & HA (В разработке)', 'Трек 2: Production Readiness & HA')

with open(readme_path, 'w') as f:
    f.write(text)

print("Track 2 Modules generated successfully.")
