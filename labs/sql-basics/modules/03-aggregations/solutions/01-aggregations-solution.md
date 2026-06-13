# Решение: Задание 1

```sql
-- 1. Общее количество аренд
SELECT COUNT(*) AS total_rentals FROM rental;

-- 2. Средняя арендная ставка по рейтингам
SELECT rating, AVG(rental_rate) AS average_rate 
FROM film 
GROUP BY rating;

-- 3. Количество аренд по каждому клиенту
SELECT customer.customer_id, customer.first_name, customer.last_name, COUNT(rental.rental_id) AS rental_count
FROM customer
LEFT JOIN rental ON customer.customer_id = rental.customer_id
GROUP BY customer.customer_id, customer.first_name, customer.last_name;

-- 4. Клиенты с более чем 30 арендами
SELECT customer.customer_id, customer.first_name, customer.last_name, COUNT(rental.rental_id) AS rental_count
FROM customer
JOIN rental ON customer.customer_id = rental.customer_id
GROUP BY customer.customer_id, customer.first_name, customer.last_name
HAVING COUNT(rental.rental_id) > 30;
```
