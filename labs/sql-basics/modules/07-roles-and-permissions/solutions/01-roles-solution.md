# Решение: Задание 1

Выполните следующие SQL-запросы в базе данных `shop_db` (подключившись от имени администратора `postgres`):

```sql
-- 1. Создание пользователя
CREATE USER test_reader WITH PASSWORD 'test_pass';

-- 2. Выдача прав на подключение
GRANT CONNECT ON DATABASE shop_db TO test_reader;

-- 3. Выдача прав на использование схемы public
GRANT USAGE ON SCHEMA public TO test_reader;

-- 4. Выдача прав на SELECT для таблицы users
GRANT SELECT ON TABLE users TO test_reader;

-- Проверка работоспособности:
-- Вы можете подключиться под созданным пользователем:
-- psql -d shop_db -U test_reader -h 127.0.0.1 -W
-- И выполнить: SELECT * FROM users; (работает)
-- А также: SELECT * FROM orders; (ошибка: permission denied)

-- 5. Очистка стенда
DROP OWNED BY test_reader CASCADE;
DROP ROLE test_reader;
```
