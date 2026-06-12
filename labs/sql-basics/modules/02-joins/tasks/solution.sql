-- 1. LEFT JOIN
SELECT users.name, orders.status 
FROM users 
LEFT JOIN orders ON users.id = orders.user_id;

-- 2. Anti-Join (Без заказов)
SELECT users.name 
FROM users 
LEFT JOIN orders ON users.id = orders.user_id 
WHERE orders.id IS NULL;

-- 3. Детализация из 4 таблиц
SELECT 
    u.name, 
    o.order_date, 
    p.name AS product_name, 
    oi.quantity, 
    (oi.quantity * oi.price_per_unit) AS total_item_price
FROM orders o
JOIN users u ON o.user_id = u.id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id
WHERE o.id = 1;
