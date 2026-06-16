-- Идемпотентность (чтобы скрипт можно было запускать несколько раз)
DO $$ 
BEGIN 
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'bi_user') THEN 
        DROP OWNED BY bi_user CASCADE; 
        DROP ROLE bi_user; 
    END IF; 
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'analytics_group') THEN 
        DROP OWNED BY analytics_group CASCADE;
        DROP ROLE analytics_group; 
    END IF; 
END $$;

-- 1. Создайте группу (роль без права логина) с именем analytics_group
CREATE ROLE analytics_group;

-- 2. Создайте пользователя с именем bi_user и паролем bi_pass_123
CREATE USER bi_user WITH PASSWORD 'bi_pass_123';

-- 3. Включите пользователя bi_user в группу analytics_group
GRANT analytics_group TO bi_user;

-- 4. Выдайте группе analytics_group права на подключение (CONNECT) к базе данных shop_db
GRANT CONNECT ON DATABASE shop_db TO analytics_group;

-- 5. Выдайте группе analytics_group права на использование (USAGE) схемы public
GRANT USAGE ON SCHEMA public TO analytics_group;

-- 6. Выдайте группе analytics_group права только на чтение (SELECT) данных из таблиц orders и products
GRANT SELECT ON TABLE orders TO analytics_group;
GRANT SELECT ON TABLE products TO analytics_group;
