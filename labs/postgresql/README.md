# PostgreSQL Labs (pg-labs)

Практический репозиторий для поэтапного освоения PostgreSQL. Содержит базовые учебные модули для настройки и работы с PostgreSQL в режиме standalone (на одном сервере).

## 🚀 Быстрый старт

Убедитесь, что у вас есть доступ к Linux-серверу с правами `root` (или sudo), где вы будете выполнять лабораторные работы. Рекомендуемая ОС: Ubuntu 22.04 / 24.04 или Debian.

## 🗺️ Карта обучения (Learning Path)

Лабораторные работы разбиты на логические треки. Начните с базового уровня и продвигайтесь к конфигурациям уровня Production (HA, пулинг соединений, продвинутый мониторинг).

## 📦 Модули

### Трек 1: Основы (Standalone)
1. [01-install-and-config](modules/01-install-and-config) — Установка PostgreSQL, базовая настройка (`postgresql.conf`, `pg_hba.conf`), запуск службы.
2. [02-users-roles](modules/02-users-roles) — Управление пользователями, ролями и правами доступа (GRANT/REVOKE).
3. [03-backup-restore](modules/03-backup-restore) — Резервное копирование и восстановление (pg_dump, pg_restore).
4. [04-maintenance](modules/04-maintenance) — Обслуживание базы данных (VACUUM, ANALYZE, мониторинг активности).

### Трек 2: Production Readiness & HA (В разработке)
Этот трек закладывает архитектуру для отказоустойчивых и высоконагруженных инсталляций.
5. [05-advanced-tuning](modules/05-advanced-tuning) *(в планах)* — Тюнинг `postgresql.conf` под железо, нагрузочное тестирование с `pgbench`.
6. [06-connection-pooling](modules/06-connection-pooling) *(в планах)* — Настройка пулеров соединений (PgBouncer, Odyssey).
7. [07-streaming-replication](modules/07-streaming-replication) *(в планах)* — Потоковая репликация (Primary - Replica) и управление WAL.
8. [08-high-availability](modules/08-high-availability) *(в планах)* — Кластеризация и автоматический failover (Patroni + etcd / Consul).
9. [09-monitoring-alerting](modules/09-monitoring-alerting) *(в планах)* — Экспорт метрик (postgres_exporter) и интеграция с Prometheus/Grafana.

## 📂 Структура каждого модуля

Внутри каждого модуля вы найдете:
- `README.md` — теория и общее описание модуля.
- `tasks/` — практические задания.
- `solutions/` — эталонные решения.
- `broken/` — (опционально) сценарии "сломанных" конфигураций для практики траблшутинга.
- `verify/` — (опционально) скрипты проверки выполнения заданий.

## ✅ QA и Верификация

(Раздел в разработке) В будущем здесь появятся автоматические скрипты проверки успешного выполнения заданий, аналогично `k8s-labs`.
