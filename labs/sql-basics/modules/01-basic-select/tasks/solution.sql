-- 1. Пагинация: вторая десятка фильмов с самой высокой стоимостью возмещения
SELECT title, replacement_cost FROM film 
ORDER BY replacement_cost DESC 
LIMIT 10 OFFSET 10;

-- 2. Поиск по тексту: описания фильмов (регистронезависимый)
SELECT title, description FROM film 
WHERE description ILIKE '%robot%';

-- 3. Работа с датами: май
SELECT rental_id, rental_date FROM rental 
WHERE EXTRACT(MONTH FROM rental_date) = 5;
