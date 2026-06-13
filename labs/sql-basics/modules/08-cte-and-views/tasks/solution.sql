-- Удаляем материализованное представление, если оно существует, для идемпотентности
DROP MATERIALIZED VIEW IF EXISTS customer_stats CASCADE;

-- 1-3. Создание материализованного представления с группировкой
CREATE MATERIALIZED VIEW customer_stats AS
SELECT 
    user_id,
    COUNT(id) AS total_orders,
    MAX(order_date) AS last_order_date
FROM orders
GROUP BY user_id;

-- 4. Создание уникального индекса для возможности использования REFRESH CONCURRENTLY
CREATE UNIQUE INDEX idx_customer_stats_user_id ON customer_stats (user_id);
