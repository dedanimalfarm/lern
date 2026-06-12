# Решение: Задание 1

```sql
-- Подключаемся к базе app_db:
-- sudo -u postgres psql -d app_db

-- 1. Генерация нагрузки
CREATE TABLE test_vac (id serial, data text);
INSERT INTO test_vac (data) SELECT 'test_string_' || generate_series(1, 100000);

-- Проверка размера (~ 4-5 MB)
SELECT pg_size_pretty(pg_relation_size('test_vac'));

-- 2. Удаление строк
DELETE FROM test_vac WHERE id % 2 = 0;

-- Размер останется прежним из-за MVCC (dead tuples)
SELECT pg_size_pretty(pg_relation_size('test_vac'));

-- 3. VACUUM и ANALYZE
-- Помечает место как свободное, но не сжимает файл (если мертвые строки не в конце)
VACUUM VERBOSE test_vac; 
-- Обновляет статистику
ANALYZE test_vac;

-- Жесткое сжатие (эксклюзивная блокировка)
VACUUM FULL test_vac;
-- Теперь размер таблицы должен уменьшиться примерно в два раза
SELECT pg_size_pretty(pg_relation_size('test_vac'));

-- 4. Просмотр активных сессий
SELECT pid, usename, state, query 
FROM pg_stat_activity 
WHERE state = 'active';
```
