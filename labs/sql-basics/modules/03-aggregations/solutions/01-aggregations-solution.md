# Решение: Задание 1

```sql
-- 1. Общее количество заказов
SELECT COUNT(*) AS total_orders FROM orders;

-- 2. Средняя цена товаров по категориям
SELECT category, AVG(price) AS average_price 
FROM products 
GROUP BY category;

-- 3. Количество заказов по каждому пользователю
SELECT users.name, COUNT(orders.id) AS orders_count
FROM users
LEFT JOIN orders ON users.id = orders.user_id
GROUP BY users.name;

-- 4. Пользователи с более чем 1 заказом
SELECT users.name, COUNT(orders.id) AS orders_count
FROM users
JOIN orders ON users.id = orders.user_id
GROUP BY users.name
HAVING COUNT(orders.id) > 1;
```
