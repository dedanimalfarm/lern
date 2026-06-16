# Решение: Задание 1

Выполните следующие SQL-запросы в базе данных `shop_db`:

```sql
-- 1. Использование CTE для расчета среднего чека
WITH order_sums AS (
    SELECT order_id, SUM(quantity * price_per_unit) AS total_amount
    FROM order_items
    GROUP BY order_id
)
SELECT AVG(total_amount) AS average_order_value
FROM order_sums;

-- 2. Создание стандартного представления (VIEW)
CREATE OR REPLACE VIEW active_products AS
SELECT id, name, price
FROM products
WHERE price > 1000;

-- 3. Проверка работы представления
SELECT * FROM active_products;

-- 4. Очистка стенда
DROP VIEW IF EXISTS active_products;
```
