-- 1. Пагинация: вторая десятка дорогих товаров
SELECT name, price FROM products 
ORDER BY price DESC 
LIMIT 10 OFFSET 10;

-- 2. Поиск по тексту: пользователи gmail (регистронезависимый)
SELECT email FROM users 
WHERE email ILIKE '%@gmail.com';

-- 3. Работа с датами: май
SELECT name, registration_date FROM users 
WHERE EXTRACT(MONTH FROM registration_date) = 5;
