import os

def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

base_pg = "/root/lern/labs/postgresql/modules/"

# ==============================================================================
# MODULE 01: INSTALL AND CONFIG
# ==============================================================================
md_01 = """# Лабораторная работа 01: Установка и базовая конфигурация PostgreSQL

## Целеполагание (Таксономия Блума)
После прохождения этого модуля вы сможете:
1. Устанавливать PostgreSQL и понимать разницу между кластером Debian и ванильным кластером.
2. Конфигурировать сетевые настройки сервера (postgresql.conf).
3. Различать методы подключения: Unix-сокет против TCP/IP.
4. Диагностировать и исправлять ошибки аутентификации (pg_hba.conf).

Время: ~30 мин | Сложность: 2/5

## Оглавление
- [Часть 1: Установка и разница подключений](#часть-1-установка-и-разница-подключений)
- [Часть 2: Настройка postgresql.conf](#часть-2-настройка-postgresqlconf)
- [Часть 3: Troubleshooting (pg_hba.conf)](#часть-3-troubleshooting-pghbaconf)
- [Вопросы для самопроверки](#вопросы-для-самопроверки)

---

## Часть 1: Установка и разница подключений

Установите PostgreSQL:
```bash
sudo apt update && sudo apt install -y postgresql postgresql-contrib
```

### Подключение через Unix-сокет vs TCP/IP
По умолчанию PostgreSQL слушает локальный Unix-сокет (обычно в `/var/run/postgresql/`). Это позволяет системному пользователю `postgres` входить без пароля (метод `peer`).
```bash
# Работает: подключение через локальный сокет
sudo -u postgres psql
```
Попробуйте подключиться через сетевой интерфейс:
```bash
# Скорее всего упадет: подключение по TCP/IP (localhost)
psql -h 127.0.0.1 -U postgres
```
Разница критична: Unix-сокет игнорирует сетевые правила `pg_hba.conf` для TCP, он использует свои собственные правила (строка `local` в файле конфигурации).

---

## Часть 2: Настройка postgresql.conf

Откройте файл `/etc/postgresql/14/main/postgresql.conf` (путь зависит от версии).
Найдите и измените следующие параметры:
```ini
listen_addresses = '*'
port = 5432
```
Перезапустите сервис:
```bash
sudo systemctl restart postgresql
ss -tlnp | grep 5432
```

---

## Часть 3: Troubleshooting (pg_hba.conf)

Перейдите в директорию `tasks/`. Запустите скрипт `prepare.sh` (он подменит ваш `pg_hba.conf` на сломанный и сделает reload).
Затем попробуйте выполнить:
```bash
psql -U postgres -h 127.0.0.1
```
Вы получите ошибку: `FATAL: Peer authentication failed for user "postgres"` (или Ident).

**Задача:**
1. Поймите, почему попытка входа по TCP использует `peer` (спойлер: метод `peer` работает только для Unix-сокетов, для TCP он не применим или требует `ident`).
2. Отредактируйте `pg_hba.conf`, изменив метод аутентификации для `host 127.0.0.1` на `scram-sha-256`.
3. Сделайте `sudo systemctl reload postgresql`.
4. Задайте пароль суперпользователю через сокет: `sudo -u postgres psql -c "\\password postgres"`.
5. Запустите `verify.sh` для проверки.

---

## Вопросы для самопроверки
1. Почему `listen_addresses = '*'` не делает сервер уязвимым сам по себе, если `pg_hba.conf` настроен строго?
2. В чем разница между `peer` и `scram-sha-256`?
"""

prep_01 = """#!/bin/bash
echo "local   all             postgres                                peer" > /etc/postgresql/14/main/pg_hba.conf
echo "host    all             all             127.0.0.1/32            peer" >> /etc/postgresql/14/main/pg_hba.conf
echo "host    all             all             ::1/128                 peer" >> /etc/postgresql/14/main/pg_hba.conf
systemctl reload postgresql
echo "Prepared broken pg_hba.conf"
"""

ver_01 = """#!/bin/bash
if PGPASSWORD=123 psql -h 127.0.0.1 -U postgres -c "SELECT 1" >/dev/null 2>&1; then
    echo "PASS: Authentication successful over TCP/IP"
else
    echo "FAIL: Cannot connect over TCP/IP"
fi
"""

clean_01 = """#!/bin/bash
# Revert to standard
echo "local   all             postgres                                peer" > /etc/postgresql/14/main/pg_hba.conf
echo "host    all             all             127.0.0.1/32            scram-sha-256" >> /etc/postgresql/14/main/pg_hba.conf
systemctl reload postgresql
echo "Cleaned up module 01"
"""

write_file(os.path.join(base_pg, "01-install-and-config/README.md"), md_01)
write_file(os.path.join(base_pg, "01-install-and-config/tasks/prepare.sh"), prep_01)
write_file(os.path.join(base_pg, "01-install-and-config/tasks/verify.sh"), ver_01)
write_file(os.path.join(base_pg, "01-install-and-config/tasks/cleanup.sh"), clean_01)

# ==============================================================================
# MODULE 02: USERS AND ROLES
# ==============================================================================
md_02 = """# Лабораторная работа 02: Пользователи, роли и права доступа

## Целеполагание (Таксономия Блума)
После прохождения этого модуля вы сможете:
1. Понимать архитектуру ролей (Role = User + Group).
2. Настраивать права доступа к схемам и таблицам.
3. Диагностировать ошибки доступа (Schema Permissions).
4. Автоматизировать выдачу прав на будущие объекты (ALTER DEFAULT PRIVILEGES).

Время: ~40 мин | Сложность: 3/5

## Оглавление
- [Часть 1: Роль как группа и как пользователь](#часть-1-роль-как-группа-и-как-пользователь)
- [Часть 2: Проблема прав на схему (Troubleshooting)](#часть-2-проблема-прав-на-схему-troubleshooting)
- [Часть 3: Настройка дефолтных привилегий](#часть-3-настройка-дефолтных-привилегий)

---

## Часть 1: Роль как группа и как пользователь

В PostgreSQL нет сущностей "пользователь" и "группа". Есть только роль. Роль с правом `LOGIN` — это пользователь. Роль без `LOGIN` — это группа.

Создадим "группу" `readonly_devs` и пользователя `john`:
```sql
CREATE ROLE readonly_devs;
CREATE ROLE john WITH LOGIN PASSWORD 'pass123';
GRANT readonly_devs TO john;
```

---

## Часть 2: Проблема прав на схему (Troubleshooting)

Запустите `prepare.sh`. Он создаст базу `dev_db`, юзера `alice` и таблицу. Юзеру `alice` выданы права: `GRANT SELECT ON ALL TABLES IN SCHEMA public TO alice`.
**Задача:** Подключитесь как `alice` (`psql -U alice -d dev_db`) и сделайте `SELECT * FROM secret_data;`.
Вы получите `ERROR: permission denied for schema public`.

Почему? Юзеру выдали права на столы, но он даже не может "войти" в схему!
**Решение:** Вернитесь под суперпользователя и выдайте `GRANT USAGE ON SCHEMA public TO alice`.

---

## Часть 3: Настройка дефолтных привилегий

Пользователю `alice` дали доступ на чтение всех таблиц. Завтра администратор создает новую таблицу `new_data`. `alice` снова получает `permission denied`. 

Команда `GRANT ... ON ALL TABLES` работает только для УЖЕ существующих таблиц.
**Задача:** Решите проблему с помощью `ALTER DEFAULT PRIVILEGES`.
```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO alice;
```

---

## Вопросы для самопроверки
1. Чем отличается `GRANT SELECT ON ALL TABLES` от `ALTER DEFAULT PRIVILEGES`?
2. Почему начиная с PostgreSQL 15 права на создание объектов в схеме `public` отозваны по умолчанию?
"""

prep_02 = """#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS dev_db;"
sudo -u postgres psql -c "CREATE DATABASE dev_db;"
sudo -u postgres psql -d dev_db -c "CREATE ROLE alice WITH LOGIN PASSWORD 'alice123';"
sudo -u postgres psql -d dev_db -c "CREATE TABLE secret_data(id int);"
sudo -u postgres psql -d dev_db -c "REVOKE ALL ON SCHEMA public FROM PUBLIC;"
sudo -u postgres psql -d dev_db -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO alice;"
echo "Prepared scenario for module 02"
"""

ver_02 = """#!/bin/bash
if PGPASSWORD=alice123 psql -h 127.0.0.1 -U alice -d dev_db -c "SELECT * FROM secret_data;" >/dev/null 2>&1; then
    echo "PASS: alice can read data"
else
    echo "FAIL: alice cannot read data (Check USAGE ON SCHEMA)"
fi
"""

clean_02 = """#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS dev_db;"
sudo -u postgres psql -c "DROP ROLE IF EXISTS alice;"
echo "Cleaned up module 02"
"""

write_file(os.path.join(base_pg, "02-users-roles/README.md"), md_02)
write_file(os.path.join(base_pg, "02-users-roles/tasks/prepare.sh"), prep_02)
write_file(os.path.join(base_pg, "02-users-roles/tasks/verify.sh"), ver_02)
write_file(os.path.join(base_pg, "02-users-roles/tasks/cleanup.sh"), clean_02)

# ==============================================================================
# MODULE 03: BACKUP AND RESTORE
# ==============================================================================
md_03 = """# Лабораторная работа 03: Резервное копирование и восстановление

## Целеполагание (Таксономия Блума)
После прохождения этого модуля вы сможете:
1. Различать логические (pg_dump) и физические (pg_basebackup) копии.
2. Создавать бэкапы в различных форматах (plain, custom).
3. Выполнять таргетное восстановление единичных таблиц.

Время: ~30 мин | Сложность: 3/5

## Оглавление
- [Часть 1: Логические против физических копий](#часть-1-логические-против-физических-копий)
- [Часть 2: Форматы pg_dump](#часть-2-форматы-pg_dump)
- [Часть 3: Таргетное восстановление из Custom формата](#часть-3-таргетное-восстановление-из-custom-формата)

---

## Часть 1: Логические против физических копий
- **pg_dump**: Логический бекап. Выгружает SQL-инструкции. Медленное восстановление, но можно восстановить 1 таблицу. Совместим между мажорными версиями.
- **pg_basebackup**: Физический бекап. Бинарное копирование файлов кластера. Очень быстрое восстановление. Нельзя восстановить 1 таблицу.

---

## Часть 2: Форматы pg_dump
Сделайте дамп базы в двух форматах:
1. Текстовый (Plain):
```bash
pg_dump -U postgres postgres -f /tmp/backup.sql
```
Его можно восстановить через `psql -f /tmp/backup.sql` или `psql < /tmp/backup.sql`.

2. Кастомный (Custom):
```bash
pg_dump -Fc -U postgres postgres -f /tmp/backup.dump
```
Кастомный формат бинарно сжат. Попытка сделать `psql < /tmp/backup.dump` выдаст ошибку кодировки. Его нужно восстанавливать только через утилиту `pg_restore`.

---

## Часть 3: Таргетное восстановление из Custom формата

Запустите `prepare.sh`. Он создаст базу данных с таблицами `users` и `logs`, затем сделает custom-бэкап в `/tmp/target.dump`, после чего удалит таблицу `users` (сымитируем ошибку джуна).

**Задача:**
Восстановите ТОЛЬКО удаленную таблицу `users` из файла `/tmp/target.dump`, не трогая таблицу `logs`.
Подсказка: используйте флаг `-t` в утилите `pg_restore`.

После восстановления запустите `verify.sh`.
"""

prep_03 = """#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS backup_db;"
sudo -u postgres psql -c "CREATE DATABASE backup_db;"
sudo -u postgres psql -d backup_db -c "CREATE TABLE users(id int);"
sudo -u postgres psql -d backup_db -c "CREATE TABLE logs(msg text);"
sudo -u postgres pg_dump -Fc backup_db -f /tmp/target.dump
sudo -u postgres psql -d backup_db -c "DROP TABLE users;"
echo "Prepared backup scenario in /tmp/target.dump"
"""

ver_03 = """#!/bin/bash
if sudo -u postgres psql -d backup_db -c "\dt" | grep -q "users"; then
    echo "PASS: Table users restored successfully"
else
    echo "FAIL: Table users not found"
fi
"""

clean_03 = """#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS backup_db;"
rm -f /tmp/target.dump /tmp/backup.sql /tmp/backup.dump
echo "Cleaned up module 03"
"""

write_file(os.path.join(base_pg, "03-backup-restore/README.md"), md_03)
write_file(os.path.join(base_pg, "03-backup-restore/tasks/prepare.sh"), prep_03)
write_file(os.path.join(base_pg, "03-backup-restore/tasks/verify.sh"), ver_03)
write_file(os.path.join(base_pg, "03-backup-restore/tasks/cleanup.sh"), clean_03)

# ==============================================================================
# MODULE 04: MAINTENANCE
# ==============================================================================
md_04 = """# Лабораторная работа 04: Обслуживание базы данных и MVCC

## Целеполагание (Таксономия Блума)
После прохождения этого модуля вы сможете:
1. Генерировать тестовые данные (pgbench).
2. Диагностировать раздувание таблиц (Bloat) с помощью расчета размеров.
3. Понимать разницу между VACUUM и VACUUM FULL.
4. Обновлять статистику (ANALYZE) и оценивать влияние на план запроса.
5. Выполнять дефрагментацию индексов (REINDEX CONCURRENTLY).

Время: ~45 мин | Сложность: 4/5

## Оглавление
- [Часть 1: Генерация данных (pgbench)](#часть-1-генерация-данных-pgbench)
- [Часть 2: Наглядность раздувания (Bloat)](#часть-2-наглядность-раздувания-bloat)
- [Часть 3: Статистика и ANALYZE](#часть-3-статистика-и-analyze)
- [Часть 4: Обслуживание индексов](#часть-4-обслуживание-индексов)

---

## Часть 1: Генерация данных (pgbench)

Утилита `pgbench` поставляется вместе с PostgreSQL и позволяет симулировать реальную нагрузку.
Запустите `prepare.sh`. Он инициализирует базу `bench_db` тестовыми данными с коэффициентом масштабирования 10 (около 1 миллиона строк).
```bash
# Как это делает prepare.sh:
# pgbench -i -s 10 bench_db
```

---

## Часть 2: Наглядность раздувания (Bloat)

Подключитесь к `bench_db`. Посмотрите текущий размер таблицы `pgbench_accounts`:
```sql
SELECT pg_size_pretty(pg_relation_size('pgbench_accounts'));
```

Сделаем 900 000 операций UPDATE:
```sql
UPDATE pgbench_accounts SET abalance = abalance + 1 WHERE aid < 900000;
```

Снова проверьте размер. Таблица увеличилась почти в 2 раза! Это "раздувание" (Bloat). При UPDATE старые строки (dead tuples) не удаляются.

Попытаемся очистить:
```sql
VACUUM VERBOSE pgbench_accounts;
```
Снова проверьте размер. Он НЕ уменьшился. Обычный `VACUUM` только помечает свободное место для будущих вставок.

Вернем место операционной системе:
```sql
VACUUM FULL VERBOSE pgbench_accounts;
```
Проверьте размер. Он уменьшился. Однако `VACUUM FULL` требует эксклюзивной блокировки, что недопустимо на 24/7 production серверах.

---

## Часть 3: Статистика и ANALYZE

Когда распределение данных меняется, оптимизатор начинает строить плохие планы. Команда `ANALYZE` обновляет статистические гистограммы.
```sql
-- План выполнения до анализа
EXPLAIN SELECT * FROM pgbench_accounts WHERE aid = 5000;

ANALYZE pgbench_accounts;

-- План выполнения после анализа
EXPLAIN SELECT * FROM pgbench_accounts WHERE aid = 5000;
```

---

## Часть 4: Обслуживание индексов

Индексы тоже подвержены фрагментации.
Команда `REINDEX INDEX idx_name;` перестраивает индекс, но блокирует запись.
В высоконагруженных системах всегда используют `CONCURRENTLY`:
```sql
REINDEX INDEX CONCURRENTLY pgbench_accounts_pkey;
```
Это создает индекс параллельно, не блокируя транзакции.

Запустите `verify.sh`.
"""

prep_04 = """#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS bench_db;"
sudo -u postgres psql -c "CREATE DATABASE bench_db;"
sudo -u postgres pgbench -i -s 10 bench_db
echo "Prepared bench_db with ~1M rows using pgbench"
"""

ver_04 = """#!/bin/bash
if sudo -u postgres psql -d bench_db -c "\dt" | grep -q "pgbench_accounts"; then
    echo "PASS: bench_db exists and is ready"
else
    echo "FAIL: pgbench failed"
fi
"""

clean_04 = """#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS bench_db;"
echo "Cleaned up module 04"
"""

write_file(os.path.join(base_pg, "04-maintenance/README.md"), md_04)
write_file(os.path.join(base_pg, "04-maintenance/tasks/prepare.sh"), prep_04)
write_file(os.path.join(base_pg, "04-maintenance/tasks/verify.sh"), ver_04)
write_file(os.path.join(base_pg, "04-maintenance/tasks/cleanup.sh"), clean_04)

for root, dirs, files in os.walk(base_pg):
    for name in files:
        if name.endswith(".sh"):
            os.chmod(os.path.join(root, name), 0o755)

print("Modules 1-4 updated with prepare, verify, and cleanup scripts!")
