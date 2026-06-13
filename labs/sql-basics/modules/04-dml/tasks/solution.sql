-- 1. Транзакция с откатом
BEGIN;
UPDATE film SET rental_rate = rental_rate * 0.5;
ROLLBACK;

-- 2. Возврат ID при вставке
INSERT INTO actor (first_name, last_name) 
VALUES ('TEST', 'ACTOR') 
RETURNING actor_id;

-- 3. UPSERT
INSERT INTO actor (actor_id, first_name, last_name)
VALUES (9999, 'TEST', 'ACTOR')
ON CONFLICT (actor_id) DO UPDATE 
SET last_update = NOW();
