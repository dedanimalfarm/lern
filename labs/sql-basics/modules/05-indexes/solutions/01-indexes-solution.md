# Решение: Задание 1

```sql
-- 1. Исследование авто-индекса (PRIMARY KEY)
EXPLAIN ANALYZE SELECT * FROM customer WHERE customer_id = 10;

-- 2. Исследование неиндексированной колонки (будет Seq Scan)
EXPLAIN ANALYZE SELECT * FROM customer WHERE create_date = '2006-02-14';

-- 3. Создание индекса
CREATE INDEX idx_customer_create_date ON customer(create_date);

-- 4. Включение форсированного использования индекса для диагностики
SET enable_seqscan = off;
EXPLAIN ANALYZE SELECT * FROM customer WHERE create_date = '2006-02-14';
RESET enable_seqscan; -- Сброс настройки обратно по умолчанию

-- 5. Очистка (удаление индекса)
DROP INDEX idx_customer_create_date;
```
