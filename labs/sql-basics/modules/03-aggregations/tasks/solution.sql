-- 1. Сумма заказа
SELECT order_id, SUM(quantity * price_per_unit) AS total_sum 
FROM order_items 
GROUP BY order_id;

-- 2. Сумма заказа > 200 000
SELECT order_id, SUM(quantity * price_per_unit) AS total_sum 
FROM order_items 
GROUP BY order_id 
HAVING SUM(quantity * price_per_unit) > 200000;

-- 3. MIN / MAX даты
SELECT MIN(order_date), MAX(order_date) FROM orders;

-- 4. Сборка строк
SELECT string_agg(p.name, ', ') 
FROM order_items oi
JOIN products p ON oi.product_id = p.id
WHERE oi.order_id = 1;

-- 5. Временные ряды (группировка по дням)
SELECT date_trunc('day', order_date) AS order_day, COUNT(*) AS orders_count 
FROM orders 
GROUP BY order_day 
ORDER BY order_day;
