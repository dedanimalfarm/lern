# Решение: Задание 1

Выполните следующие SQL-запросы в базе данных `pagila` (подключившись от имени администратора `postgres`):

```sql
-- 1. Создание пользователя
CREATE USER test_reader WITH PASSWORD 'test_pass';

-- 2. Выдача прав на подключение
GRANT CONNECT ON DATABASE pagila TO test_reader;

-- 3. Выдача прав на использование схемы public
GRANT USAGE ON SCHEMA public TO test_reader;

-- 4. Выдача прав на SELECT для таблицы customer
GRANT SELECT ON TABLE customer TO test_reader;

-- Проверка работоспособности:
-- Вы можете подключиться под созданным пользователем:
-- psql -d pagila -U test_reader -h 127.0.0.1 -W
-- И выполнить: SELECT * FROM customer; (работает)
-- А также: SELECT * FROM payment; (ошибка: permission denied)

-- 5. Очистка стенда
DROP OWNED BY test_reader CASCADE;
DROP ROLE test_reader;
```
