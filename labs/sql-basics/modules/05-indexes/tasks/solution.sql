-- 1. Диагностика сложного поиска (BUFFERS)
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM film WHERE rating = 'R' AND rental_rate > 2.00;

-- 2. Создание составного индекса
CREATE INDEX idx_film_rating_rate ON film(rating, rental_rate);

-- 3. Проверка составного индекса
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM film WHERE rating = 'R' AND rental_rate > 2.00;
RESET enable_seqscan;

-- 4. Частичный индекс (Partial Index)
CREATE INDEX idx_rental_not_returned ON rental(customer_id) WHERE return_date IS NULL;

-- 5. Покрывающий индекс (Covering Index)
CREATE INDEX idx_film_covering ON film(rating) INCLUDE (title, rental_rate);

-- 6. Очистка стенда
DROP INDEX IF EXISTS idx_film_rating_rate;
DROP INDEX IF EXISTS idx_rental_not_returned;
DROP INDEX IF EXISTS idx_film_covering;
