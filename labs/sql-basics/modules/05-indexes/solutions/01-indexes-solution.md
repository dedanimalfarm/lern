# Решение: Задание 1

```sql
-- 1. Исследование авто-индекса (PRIMARY KEY / UNIQUE)
EXPLAIN ANALYZE SELECT * FROM products WHERE name = 'Product_25';

-- 2. Исследование неиндексированной колонки (будет Seq Scan)
EXPLAIN ANALYZE SELECT * FROM users WHERE registration_date = '2026-05-15';

-- 3. Создание индекса
CREATE INDEX idx_users_reg_date ON users(registration_date);

-- 4. Включение форсированного использования индекса для диагностики
SET enable_seqscan = off;
EXPLAIN ANALYZE SELECT * FROM users WHERE registration_date = '2026-05-15';
RESET enable_seqscan; -- Сброс настройки обратно по умолчанию

-- 5. Очистка (удаление индекса)
DROP INDEX idx_users_reg_date;
```
