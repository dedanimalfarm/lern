-- 1. LEFT JOIN
SELECT film.title, inventory.inventory_id 
FROM film 
LEFT JOIN inventory ON film.film_id = inventory.film_id;

-- 2. Anti-Join (Без инвентаря)
SELECT film.title 
FROM film 
LEFT JOIN inventory ON film.film_id = inventory.film_id 
WHERE inventory.inventory_id IS NULL;

-- 3. Детализация из 5 таблиц
SELECT 
    c.first_name, 
    r.rental_date, 
    f.title AS film_title, 
    p.amount
FROM rental r
JOIN customer c ON r.customer_id = c.customer_id
JOIN inventory i ON r.inventory_id = i.inventory_id
JOIN film f ON i.film_id = f.film_id
JOIN payment p ON r.rental_id = p.rental_id
WHERE r.rental_id = 1;
