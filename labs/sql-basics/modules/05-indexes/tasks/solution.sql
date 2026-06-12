-- 1. Диагностика сложного поиска (будет Seq Scan)
EXPLAIN ANALYZE SELECT * FROM products WHERE category = 'Электроника' AND price > 50000;

-- 2. Создание составного индекса
CREATE INDEX idx_products_cat_price ON products(category, price);

-- 3. Проверка составного индекса (с отключением seqscan для маленькой таблицы)
SET enable_seqscan = off;
EXPLAIN ANALYZE SELECT * FROM products WHERE category = 'Электроника' AND price > 50000;
RESET enable_seqscan;

-- 4. Очистка стенда
DROP INDEX idx_products_cat_price;
