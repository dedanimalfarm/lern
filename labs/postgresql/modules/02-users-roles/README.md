# Лабораторная работа 02: Пользователи, роли и права доступа

## Оглавление
- [Часть 1: Концепция ролей в PostgreSQL](#часть-1-концепция-ролей-в-postgresql)
- [Часть 2: Создание ролей и выдача базовых прав](#часть-2-создание-ролей-и-выдача-базовых-прав)
- [Часть 3: Наследование ролей и групповые политики](#часть-3-наследование-ролей-и-групповые-политики)
- [Часть 4: Изоляция на уровне строк (Row Level Security)](#часть-4-изоляция-на-уровне-строк-row-level-security)
- [Часть 5: Troubleshooting - проблема с доступом к новым таблицам](#часть-5-troubleshooting)
- [Вопросы для самопроверки](#вопросы-для-самопроверки)

Время: ~40 мин | Сложность: 3/5

Цель: глубоко изучить модель управления доступом Role-Based Access Control (RBAC), понять нюансы прав на схемы и научиться автоматизировать выдачу прав на будущие объекты.

---

## Часть 1: Концепция ролей в PostgreSQL

В PostgreSQL нет жесткого разделения на "группы" и "пользователей". Всё является "ролью" (Role).
Если роль имеет атрибут `LOGIN`, мы называем ее пользователем. Если не имеет, она используется как группа. Системный каталог `pg_roles` содержит информацию обо всех ролях.

---

## Часть 2: Создание ролей и выдача базовых прав

Подключитесь к СУБД:
```bash
sudo -u postgres psql
```

Создайте базу данных и новую роль:
```sql
CREATE DATABASE app_db;
CREATE ROLE app_user WITH LOGIN PASSWORD 'secure_pass_123';
```

Попробуйте подключиться под новым пользователем и создать таблицу. Вы получите ошибку, так как начиная с PostgreSQL 15 права на создание в схеме `public` по умолчанию отобраны. Выдайте их от имени суперпользователя:
```sql
GRANT ALL ON SCHEMA public TO app_user;
```

---

## Часть 3: Наследование ролей и групповые политики

Создадим "группу" для аналитиков:
```sql
CREATE ROLE readonly_users;
CREATE ROLE analyst WITH LOGIN PASSWORD 'analyst_pass';
GRANT readonly_users TO analyst;
```

Выдадим права на чтение всех существующих таблиц группе:
```sql
GRANT USAGE ON SCHEMA public TO readonly_users;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_users;
```

---

## Часть 4: Изоляция на уровне строк (Row Level Security)

PostgreSQL позволяет ограничивать доступ не только к таблицам, но и к конкретным строкам.

```sql
CREATE TABLE tenant_data (
    id SERIAL PRIMARY KEY,
    tenant_name VARCHAR(50),
    secret_data TEXT
);

INSERT INTO tenant_data (tenant_name, secret_data) VALUES ('analyst', 'data 1'), ('admin', 'data 2');

ALTER TABLE tenant_data ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_policy ON tenant_data
    USING (tenant_name = current_user);
    
GRANT SELECT ON tenant_data TO analyst;
```
Пользователь `analyst` увидит только свои строки.

---

## Часть 5: Troubleshooting

**Сценарий:** Вы выполнили `GRANT SELECT ON ALL TABLES`. Разработчик создал новую таблицу `new_sales`. Пользователь `analyst` получает ошибку при попытке чтения `new_sales`.
**Причина:** Команда `GRANT ON ALL TABLES` применяется только к УЖЕ СУЩЕСТВУЮЩИМ таблицам.
**Решение:** Измените дефолтные привилегии.
```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO readonly_users;
```

---

## Вопросы для самопроверки
1. Что дает атрибут `CREATEROLE`? Почему его опасно выдавать недоверенным пользователям?
2. В чем отличие между `GRANT` и `ALTER DEFAULT PRIVILEGES`?
3. Пользователь имеет атрибут `BYPASSRLS`. Что это означает?
4. Как отозвать все права пользователя перед его удалением (команда `DROP OWNED`)?
