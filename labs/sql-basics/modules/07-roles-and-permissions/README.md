# Лабораторная работа 07: Управление доступом и безопасность (Roles & Permissions)

## Оглавление
- [Предварительные требования](#предварительные-требования)
- [Часть 1: Роли и пользователи](#часть-1-роли-и-пользователи)
- [Часть 2: Выдача и отзыв привилегий (GRANT / REVOKE)](#часть-2-выдача-и-отзыв-привилегий-grant--revoke)
- [Часть 3: Принцип наименьших привилегий (Least Privilege)](#часть-3-принцип-наименьших-привилегий)
- [Вопросы для самопроверки](#вопросы-для-самопроверки)

Время: ~25 мин | Сложность: 3/5

Цель: изучить механизмы управления доступом в PostgreSQL, научиться создавать роли (пользователей) и точечно выдавать им права на объекты базы данных.

---

## Предварительные требования
База данных `shop_db` и все необходимые таблицы (`users`, `orders`, `products`, `order_items`) уже созданы и наполнены данными при запуске окружения. Никаких дополнительных действий для инициализации БД выполнять не требуется.

---

## Часть 1: Роли и пользователи

В PostgreSQL понятия "роль" (role) и "пользователь" (user) практически идентичны. Команда `CREATE USER` является псевдонимом для `CREATE ROLE ... LOGIN`. Роль может представлять как конкретного человека/приложение, так и группу пользователей.

```sql
-- Создание роли без права логина (группа)
CREATE ROLE analytics_team;

-- Создание пользователя с паролем и правом на подключение (логин)
CREATE USER analytics_user WITH PASSWORD 'strong_password';

-- Включение пользователя analytics_user в группу analytics_team
GRANT analytics_team TO analytics_user;
```

Для просмотра всех ролей в базе можно использовать psql-команду `\du` или SQL-запрос:
```sql
SELECT rolname, rolsuper, rolcanlogin FROM pg_roles;
```

---

## Часть 2: Выдача и отзыв привилегий (GRANT / REVOKE)

По умолчанию новый пользователь не имеет прав на таблицы (даже на `SELECT`). Доступ необходимо выдавать явно с помощью команды `GRANT`.

```sql
-- Дать права на подключение к базе
GRANT CONNECT ON DATABASE shop_db TO analytics_team;

-- Дать права на использование схемы public
GRANT USAGE ON SCHEMA public TO analytics_team;

-- Выдать права только на чтение (SELECT) для конкретной таблицы
GRANT SELECT ON TABLE orders TO analytics_team;

-- Выдать права на чтение всех существующих таблиц в схеме public
GRANT SELECT ON ALL TABLES IN SCHEMA public TO analytics_team;
```

Для отзыва прав используется команда `REVOKE`:
```sql
-- Запретить группе удалять данные из таблицы users
REVOKE DELETE ON TABLE users FROM analytics_team;
```

---

## Часть 3: Принцип наименьших привилегий

В DevOps и администрировании баз данных критически важен принцип наименьших привилегий (Least Privilege). Приложению или пользователю выдаются только те права, которые абсолютно необходимы для его работы.

Например, микросервису "Каталог" нужны права на чтение и изменение товаров, но не должно быть доступа к таблице `users` или `orders`.
```sql
-- Пользователь сервиса каталога
CREATE USER catalog_service WITH PASSWORD 'secret';
GRANT CONNECT ON DATABASE shop_db TO catalog_service;
GRANT USAGE ON SCHEMA public TO catalog_service;

-- Разрешаем все базовые операции (CRUD) только на одну таблицу
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE products TO catalog_service;
```

**DevOps-инсайт:** Чтобы новые таблицы, создаваемые в будущем, автоматически получали правильные доступы, используется команда `ALTER DEFAULT PRIVILEGES`.

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO analytics_team;
```

---

## Вопросы для самопроверки
1. В чем разница между `CREATE ROLE` и `CREATE USER` в PostgreSQL?
2. Что делает команда `GRANT USAGE ON SCHEMA public TO my_user` и почему без нее пользователь не сможет сделать `SELECT` даже если выдать права на таблицу?
3. Как проверить, какие права выданы конкретному пользователю на таблицу? (Подсказка: psql-команда `\dp` или `\z`)
