# Лабораторная работа 02: Пользователи, роли и права доступа

## Целеполагание (Таксономия Блума)
После прохождения этого модуля вы сможете:
1. Понимать архитектуру ролей (Role = User + Group).
2. Настраивать права доступа к схемам и таблицам.
3. Диагностировать ошибки доступа (Schema Permissions).
4. Автоматизировать выдачу прав на будущие объекты (ALTER DEFAULT PRIVILEGES).

Время: ~40 мин | Сложность: 3/5

## Оглавление
- [Часть 1: Роль как группа и как пользователь](#часть-1-роль-как-группа-и-как-пользователь)
- [Часть 2: Проблема прав на схему (Troubleshooting)](#часть-2-проблема-прав-на-схему-troubleshooting)
- [Часть 3: Настройка дефолтных привилегий](#часть-3-настройка-дефолтных-привилегий)

---

## Часть 1: Роль как группа и как пользователь

В PostgreSQL нет сущностей "пользователь" и "группа". Есть только роль. Роль с правом `LOGIN` — это пользователь. Роль без `LOGIN` — это группа.

Создадим "группу" `readonly_devs` и пользователя `john`:
```sql
CREATE ROLE readonly_devs;
CREATE ROLE john WITH LOGIN PASSWORD 'pass123';
GRANT readonly_devs TO john;
```

---

## Часть 2: Проблема прав на схему (Troubleshooting)

Запустите `prepare.sh`. Он создаст базу `dev_db`, юзера `alice` и таблицу. Юзеру `alice` выданы права: `GRANT SELECT ON ALL TABLES IN SCHEMA public TO alice`.
**Задача:** Подключитесь как `alice` (`psql -U alice -d dev_db`) и сделайте `SELECT * FROM secret_data;`.
Вы получите `ERROR: permission denied for schema public`.

Почему? Юзеру выдали права на столы, но он даже не может "войти" в схему!
**Решение:** Вернитесь под суперпользователя и выдайте `GRANT USAGE ON SCHEMA public TO alice`.

---

## Часть 3: Настройка дефолтных привилегий

Пользователю `alice` дали доступ на чтение всех таблиц. Завтра администратор создает новую таблицу `new_data`. `alice` снова получает `permission denied`. 

Команда `GRANT ... ON ALL TABLES` работает только для УЖЕ существующих таблиц.
**Задача:** Решите проблему с помощью `ALTER DEFAULT PRIVILEGES`.
```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO alice;
```

---

## Вопросы для самопроверки
1. Чем отличается `GRANT SELECT ON ALL TABLES` от `ALTER DEFAULT PRIVILEGES`?
2. Почему начиная с PostgreSQL 15 права на создание объектов в схеме `public` отозваны по умолчанию?
