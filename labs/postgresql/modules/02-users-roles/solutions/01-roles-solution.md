# Решение: Задание 1

```sql
-- Подключаемся как postgres (sudo -u postgres psql)

-- 1. Создание базы данных
CREATE DATABASE app_db;

-- 2. Создание пользователей
CREATE USER app_user WITH PASSWORD 'app_password';
CREATE USER app_reader WITH PASSWORD 'read_password';

-- Подключаемся к новой базе
\c app_db

-- 3. Создание структуры
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50)
);
INSERT INTO users (username) VALUES ('admin');

-- 4. Выдача прав
-- Для app_user (полный доступ в public)
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO app_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO app_user;
-- (Чтобы права применялись и к будущим таблицам):
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO app_user;

-- Для app_reader (только чтение)
GRANT USAGE ON SCHEMA public TO app_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_reader;
-- (Для будущих таблиц):
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_reader;

```

### Проверка в bash
```bash
# Проверка read-only
psql -U app_reader -d app_db -h 127.0.0.1 -c "SELECT * FROM users;"
psql -U app_reader -d app_db -h 127.0.0.1 -c "INSERT INTO users (username) VALUES ('test');" # Вызовет ошибку

# Проверка записи
psql -U app_user -d app_db -h 127.0.0.1 -c "INSERT INTO users (username) VALUES ('test_user');"
```
