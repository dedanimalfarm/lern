# Решение: Задание 1

```sql
-- 1. Список аренд и имена клиентов (INNER JOIN)
SELECT rental.rental_id, rental.rental_date, customer.first_name 
FROM rental
JOIN customer ON rental.customer_id = customer.customer_id;

-- 2. Все фильмы и их копии в инвентаре (LEFT JOIN)
SELECT film.title, inventory.inventory_id 
FROM film
LEFT JOIN inventory ON film.film_id = inventory.film_id;

-- 3. Детализация аренды №1 (5 таблиц)
SELECT 
    customer.first_name AS user_name,
    rental.rental_date,
    film.title AS film_title,
    payment.amount
FROM rental
JOIN customer ON rental.customer_id = customer.customer_id
JOIN inventory ON rental.inventory_id = inventory.inventory_id
JOIN film ON inventory.film_id = film.film_id
JOIN payment ON rental.rental_id = payment.rental_id
WHERE rental.rental_id = 1;
```
