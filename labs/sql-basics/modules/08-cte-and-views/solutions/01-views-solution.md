# Решение: Задание 1

Выполните следующие SQL-запросы в базе данных `pagila`:

```sql
-- 1. Использование CTE для расчета среднего платежа по клиентам
WITH customer_payments AS (
    SELECT customer_id, SUM(amount) AS total_amount
    FROM payment
    GROUP BY customer_id
)
SELECT AVG(total_amount) AS average_customer_payments
FROM customer_payments;

-- 2. Создание стандартного представления (VIEW)
CREATE OR REPLACE VIEW premium_films AS
SELECT film_id, title, rental_rate
FROM film
WHERE rental_rate > 4.00;

-- 3. Проверка работы представления
SELECT * FROM premium_films;

-- 4. Очистка стенда
DROP VIEW IF EXISTS premium_films;
```
