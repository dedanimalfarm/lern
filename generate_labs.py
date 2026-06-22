import os

def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

# ==========================================
# POSTGRESQL MODULES
# ==========================================

pg_mod1 = """# Лабораторная работа 01: Установка и базовая конфигурация PostgreSQL

## Оглавление
- [Предварительные требования](#предварительные-требования)
- [Часть 1: Установка и системный сервис](#часть-1-установка-и-системный-сервис)
- [Часть 2: Настройка сетевого доступа](#часть-2-настройка-сетевого-доступа)
- [Часть 3: Troubleshooting (боевые инциденты)](#часть-3-troubleshooting)
- [Вопросы для самопроверки](#вопросы-для-самопроверки)

> ⏱ время ~15 мин · сложность 1/5 · пререквизиты: базовое знание Linux (apt, systemd)

Цель: научиться устанавливать PostgreSQL, управлять сервисом и настраивать клиентскую аутентификацию.

---

## Предварительные требования
Доступ к Linux серверу (Ubuntu/Debian) с правами root.

---

## Часть 1: Установка и системный сервис

### Теория для изучения перед частью
PostgreSQL в Ubuntu/Debian по умолчанию создает кластер базы данных в `/var/lib/postgresql/<version>/main` и конфигурационные файлы в `/etc/postgresql/<version>/main`.

### Практика
Установим СУБД:
```bash
sudo apt update && sudo apt install -y postgresql postgresql-contrib
```
Проверим статус:
```bash
systemctl status postgresql
```

---

## Часть 2: Настройка сетевого доступа

### Теория для изучения перед частью
- `postgresql.conf` — `listen_addresses` (какие интерфейсы слушать).
- `pg_hba.conf` — кто, откуда и как может подключаться.

### Практика
Откроем доступ извне:
```bash
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/14/main/postgresql.conf
echo "host    all             all             0.0.0.0/0               md5" | sudo tee -a /etc/postgresql/14/main/pg_hba.conf
sudo systemctl restart postgresql
```

---

## Часть 3: Troubleshooting

В директории `broken/scenario-01` лежит сломанный конфиг.
Сценарий: Вы не можете подключиться к СУБД снаружи.
**Задание:** Замените свой `pg_hba.conf` на сломанный, перезапустите сервис, попытайтесь подключиться и найдите ошибку в логах (или в самом файле).

---

## Вопросы для самопроверки
1. Чем отличается аутентификация `peer` от `md5`?
2. В каком файле настраиваются параметры выделяемой памяти (shared_buffers)?

👉 **Практика:** Перейдите в папку `tasks/` для самостоятельной работы.
"""

pg_mod1_broken = """# Сломанный pg_hba.conf
local   all             postgres                                peer
host    all             all             127.0.0.1/32            md5
host    all             all             192.168.1.100/32        reject
host    all             all             0.0.0.0/0               reject
"""

pg_mod2 = """# Лабораторная работа 02: Пользователи, роли и права доступа

## Оглавление
- [Предварительные требования](#предварительные-требования)
- [Часть 1: Создание ролей](#часть-1-создание-ролей)
- [Часть 2: Выдача прав (GRANT)](#часть-2-выдача-прав)
- [Часть 3: Troubleshooting](#часть-3-troubleshooting)
- [Вопросы для самопроверки](#вопросы-для-самопроверки)

> ⏱ время ~20 мин · сложность 2/5

Цель: научиться управлять RBAC (Role-Based Access Control) в PostgreSQL.

---

## Часть 1: Создание ролей

### Теория
В PostgreSQL нет понятия "пользователь" и "группа", есть только "Роль" (Role). Если роль имеет атрибут `LOGIN`, она выступает как пользователь.

### Практика
```sql
CREATE ROLE app_user WITH LOGIN PASSWORD 'secret';
-- или
CREATE USER app_user WITH PASSWORD 'secret';
```

---

## Часть 2: Выдача прав (GRANT)

### Теория
Права выдаются на конкретные объекты (таблицы, схемы) с помощью команды `GRANT`.

### Практика
```sql
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_user;
```

---

## Часть 3: Troubleshooting

Сценарий: Пользователь `app_user` жалуется, что при создании новых таблиц другим администратором, он не может их читать, хотя ему выдали `GRANT SELECT ON ALL TABLES`.
**Решение:** Изучите команду `ALTER DEFAULT PRIVILEGES`.

---

## Вопросы для самопроверки
1. Что такое `SUPERUSER` и почему его нельзя давать приложениям?
2. Почему после создания новой таблицы пользователь с `GRANT SELECT ON ALL TABLES` не имеет к ней доступа?

👉 **Практика:** Перейдите в папку `tasks/`.
"""

pg_mod3 = """# Лабораторная работа 03: Резервное копирование и восстановление

## Оглавление
- [Часть 1: Логический дамп (pg_dump)](#часть-1-логический-дамп)
- [Часть 2: Восстановление (pg_restore)](#часть-2-восстановление)
- [Часть 3: Troubleshooting](#часть-3-troubleshooting)

> ⏱ время ~20 мин · сложность 2/5

Цель: научиться делать логические бэкапы и восстанавливать их.

---

## Часть 1: Логический дамп

### Теория
`pg_dump` делает логический срез базы. Формат `-Fc` (custom) сжимает данные и позволяет выборочно восстанавливать таблицы.

### Практика
```bash
pg_dump -Fc shop_db -f /tmp/shop_backup.dump
```

---

## Часть 2: Восстановление

### Практика
Имитируем аварию: `DROP DATABASE shop_db; CREATE DATABASE shop_db;`
Восстанавливаем:
```bash
pg_restore -d shop_db /tmp/shop_backup.dump
```

---

## Часть 3: Troubleshooting

Сценарий: бэкап был прерван на середине. Файл дампа поврежден.
**Задание:** Попробуйте восстановить поврежденный дамп и изучите вывод ошибок `pg_restore`.

---

## Вопросы для самопроверки
1. Чем логический бэкап отличается от физического (Base backup)?
2. Как восстановить только одну таблицу из `.dump` файла?

👉 **Практика:** Перейдите в папку `tasks/`.
"""

pg_mod4 = """# Лабораторная работа 04: Обслуживание базы данных

## Оглавление
- [Часть 1: MVCC и "мертвые" строки](#часть-1-mvcc-и-мертвые-строки)
- [Часть 2: VACUUM и ANALYZE](#часть-2-vacuum-и-analyze)

> ⏱ время ~15 мин · сложность 3/5

Цель: понять, как PostgreSQL управляет версиями строк и зачем нужна очистка.

---

## Часть 1: MVCC и "мертвые" строки

### Теория
При `UPDATE` и `DELETE` строки не удаляются физически, а помечаются как невидимые (dead tuples). Это основа MVCC (Multi-Version Concurrency Control).

---

## Часть 2: VACUUM и ANALYZE

### Практика
```sql
DELETE FROM large_table WHERE id % 2 = 0;
VACUUM VERBOSE large_table;
ANALYZE large_table;
```

---

## Вопросы для самопроверки
1. Почему размер файла таблицы не уменьшается после `VACUUM`?
2. В чем опасность `VACUUM FULL` в production?

👉 **Практика:** Перейдите в папку `tasks/`.
"""

# ==========================================
# SQL BASICS MODULES
# ==========================================

sql_mod1 = """# Лабораторная работа 01: Основы выборки данных (SELECT)

## Оглавление
- [Предварительные требования](#предварительные-требования)
- [Часть 1: Базовая выборка](#часть-1-базовая-выборка)
- [Часть 2: Фильтрация (WHERE)](#часть-2-фильтрация)
- [Часть 3: Troubleshooting](#часть-3-troubleshooting)

> ⏱ время ~15 мин · сложность 1/5

Цель: научиться извлекать данные из БД.

---

## Часть 1: Базовая выборка

### Практика
```sql
SELECT name, price FROM products;
```

---

## Часть 2: Фильтрация (WHERE)

### Теория
Используйте `WHERE`, чтобы ограничить строки.
### Практика
```sql
SELECT * FROM products WHERE price > 50000 ORDER BY price DESC LIMIT 3;
```

---

## Часть 3: Troubleshooting

**Сценарий:** Запрос `SELECT * FROM users WHERE name = "Иван Иванов";` возвращает ошибку `column "Иван Иванов" does not exist`.
**Объяснение:** В SQL двойные кавычки `""` обозначают имена столбцов/таблиц, а одинарные `''` — строковые значения. Замените на одинарные.

---

## Вопросы для самопроверки
1. Как работает `DISTINCT`?
2. В каком порядке выполняются `WHERE` и `ORDER BY`?

👉 **Практика:** Перейдите в папку `tasks/`.
"""

sql_mod2 = """# Лабораторная работа 02: Соединение таблиц (JOIN)

## Оглавление
- [Часть 1: INNER JOIN](#часть-1-inner-join)
- [Часть 2: LEFT JOIN](#часть-2-left-join)
- [Часть 3: Troubleshooting](#часть-3-troubleshooting)

> ⏱ время ~25 мин · сложность 3/5

Цель: научиться связывать данные из нескольких таблиц.

---

## Часть 1: INNER JOIN

### Теория
Возвращает только те строки, для которых есть совпадения в обеих таблицах.
### Практика
```sql
SELECT orders.id, users.name FROM orders INNER JOIN users ON orders.user_id = users.id;
```

---

## Часть 2: LEFT JOIN

### Теория
Возвращает все строки из первой таблицы, даже если нет совпадений во второй (тогда подставляет `NULL`).
### Практика
```sql
SELECT users.name, orders.id FROM users LEFT JOIN orders ON users.id = orders.user_id;
```

---

## Часть 3: Troubleshooting

**Сценарий:** При JOIN двух больших таблиц без условия `ON` вы получаете "зависший" запрос или огромную выдачу.
**Объяснение:** Это `CROSS JOIN` (Декартово произведение) - каждая строка соединилась с каждой. Всегда указывайте условие связывания!

---

## Вопросы для самопроверки
1. Что вернет `LEFT JOIN`, если во второй таблице есть несколько совпадающих строк для одной строки из первой?

👉 **Практика:** Перейдите в папку `tasks/`.
"""

sql_mod3 = """# Лабораторная работа 03: Агрегация и группировка данных

## Оглавление
- [Часть 1: Агрегатные функции](#часть-1-агрегатные-функции)
- [Часть 2: GROUP BY и HAVING](#часть-2-group-by-и-having)

> ⏱ время ~20 мин · сложность 2/5

Цель: научиться считать статистику.

---

## Часть 1: Агрегатные функции
```sql
SELECT COUNT(*), AVG(price) FROM products;
```

---

## Часть 2: GROUP BY и HAVING
```sql
SELECT category, AVG(price) FROM products GROUP BY category HAVING AVG(price) > 10000;
```

---

## Вопросы для самопроверки
1. Можно ли использовать `WHERE` и `HAVING` вместе? В каком порядке?
2. Почему неагрегированные поля в `SELECT` должны быть в `GROUP BY`?

👉 **Практика:** Перейдите в папку `tasks/`.
"""

sql_mod4 = """# Лабораторная работа 04: Управление данными (DML)

## Оглавление
- [Часть 1: Вставка данных (INSERT)](#часть-1-вставка-данных)
- [Часть 2: Обновление и Удаление](#часть-2-обновление-и-удаление)
- [Часть 3: Troubleshooting](#часть-3-troubleshooting)

> ⏱ время ~15 мин · сложность 2/5

Цель: научиться изменять данные.

---

## Часть 1: Вставка данных
```sql
INSERT INTO users (name, email) VALUES ('Alex', 'alex@mail.com');
```

---

## Часть 2: Обновление и Удаление
```sql
UPDATE products SET price = price * 0.9 WHERE category = 'Accessories';
DELETE FROM orders WHERE status = 'CANCELLED';
```

---

## Часть 3: Troubleshooting

**Сценарий:** Забыли `WHERE` в запросе `UPDATE` или `DELETE`.
**Урок:** Данные изменятся для ВСЕХ строк таблицы. В production всегда делайте `BEGIN; UPDATE ...; COMMIT;` (или `ROLLBACK;` если ошиблись).

---

## Вопросы для самопроверки
1. Чем `DELETE` отличается от `TRUNCATE`?

👉 **Практика:** Перейдите в папку `tasks/`.
"""

# Path to write to
base_pg = "/root/lern/labs/postgresql/modules/"
base_sql = "/root/lern/labs/sql-basics/modules/"

write_file(os.path.join(base_pg, "01-install-and-config/README.md"), pg_mod1)
write_file(os.path.join(base_pg, "01-install-and-config/broken/scenario-01/pg_hba.conf"), pg_mod1_broken)
write_file(os.path.join(base_pg, "02-users-roles/README.md"), pg_mod2)
write_file(os.path.join(base_pg, "03-backup-restore/README.md"), pg_mod3)
write_file(os.path.join(base_pg, "04-maintenance/README.md"), pg_mod4)

write_file(os.path.join(base_sql, "01-basic-select/README.md"), sql_mod1)
write_file(os.path.join(base_sql, "02-joins/README.md"), sql_mod2)
write_file(os.path.join(base_sql, "03-aggregations/README.md"), sql_mod3)
write_file(os.path.join(base_sql, "04-dml/README.md"), sql_mod4)

print("All modules generated successfully!")
