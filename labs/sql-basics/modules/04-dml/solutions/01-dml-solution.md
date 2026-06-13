# Решение: Задание 1

```sql
-- 1. Добавление актера
INSERT INTO actor (first_name, last_name) 
VALUES ('JOHN', 'DOE');

-- 2. Скидка 10% на фильмы с рейтингом 'G'
UPDATE film 
SET rental_rate = rental_rate * 0.9 
WHERE rating = 'G';

-- 3. Удаление ошибочного платежа (№10000)
DELETE FROM payment 
WHERE payment_id = 10000;
```
