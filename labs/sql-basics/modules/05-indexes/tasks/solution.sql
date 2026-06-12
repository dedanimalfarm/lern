-- 1. Диагностика сложного поиска (BUFFERS)
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM products WHERE category = 'Электроника' AND price > 50000;

-- 2. Создание составного индекса
CREATE INDEX idx_products_cat_price ON products(category, price);

-- 3. Проверка составного индекса
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM products WHERE category = 'Электроника' AND price > 50000;
RESET enable_seqscan;

-- 4. Частичный индекс (Partial Index)
CREATE INDEX idx_orders_cancelled ON orders(user_id) WHERE status = 'CANCELLED';

-- 5. Покрывающий индекс (Covering Index)
CREATE INDEX idx_products_covering ON products(category) INCLUDE (name, price);

-- 6. Очистка стенда
DROP INDEX IF EXISTS idx_products_cat_price;
DROP INDEX IF EXISTS idx_orders_cancelled;
DROP INDEX IF EXISTS idx_products_covering;
