# Решение: Задание 1

```sql
-- 1. Вывести имена и цены всех товаров
SELECT name, price FROM products;

-- 2. Электроника дешевле 100 000
SELECT * FROM products 
WHERE category = 'Электроника' AND price < 100000;

-- 3. Топ-3 самых дорогих товара
SELECT * FROM products 
ORDER BY price DESC 
LIMIT 3;

-- 4. Пользователи с заполненной датой регистрации (не NULL)
SELECT name FROM users 
WHERE registration_date IS NOT NULL;
```
