-- Удаляем материализованное представление, если оно существует, для идемпотентности
DROP MATERIALIZED VIEW IF EXISTS customer_stats CASCADE;

-- 1-3. Создание материализованного представления с группировкой
CREATE MATERIALIZED VIEW customer_stats AS
SELECT 
    customer_id,
    COUNT(payment_id) AS total_payments,
    MAX(payment_date) AS last_payment_date
FROM payment
GROUP BY customer_id;

-- 4. Создание уникального индекса для возможности использования REFRESH CONCURRENTLY
CREATE UNIQUE INDEX idx_customer_stats_customer_id ON customer_stats (customer_id);
