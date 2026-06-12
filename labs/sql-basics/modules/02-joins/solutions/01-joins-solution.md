# Решение: Задание 1

```sql
-- 1. Список заказов и имена покупателей (INNER JOIN)
SELECT orders.id AS order_id, orders.order_date, users.name 
FROM orders
JOIN users ON orders.user_id = users.id;

-- 2. Все пользователи и их заказы (LEFT JOIN)
SELECT users.name, orders.order_date 
FROM users
LEFT JOIN orders ON users.id = orders.user_id;

-- 3. Детализация заказа №1 (4 таблицы)
SELECT 
    users.name AS user_name,
    orders.order_date,
    products.name AS product_name,
    order_items.quantity,
    order_items.price_per_unit
FROM orders
JOIN users ON orders.user_id = users.id
JOIN order_items ON orders.id = order_items.order_id
JOIN products ON order_items.product_id = products.id
WHERE orders.id = 1;
```
