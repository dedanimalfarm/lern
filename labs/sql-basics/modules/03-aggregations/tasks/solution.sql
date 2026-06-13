-- 1. Сумма платежей клиента
SELECT customer_id, SUM(amount) AS total_sum 
FROM payment 
GROUP BY customer_id;

-- 2. Сумма платежей > 180.00
SELECT customer_id, SUM(amount) AS total_sum 
FROM payment 
GROUP BY customer_id 
HAVING SUM(amount) > 180.00;

-- 3. MIN / MAX даты
SELECT MIN(rental_date), MAX(rental_date) FROM rental;

-- 4. Сборка строк
SELECT string_agg(f.title, ', ') 
FROM rental r
JOIN inventory i ON r.inventory_id = i.inventory_id
JOIN film f ON i.film_id = f.film_id
WHERE r.customer_id = 1;

-- 5. Временные ряды (группировка по дням)
SELECT date_trunc('day', rental_date) AS rental_day, COUNT(*) AS rental_count 
FROM rental 
GROUP BY rental_day 
ORDER BY rental_day;
