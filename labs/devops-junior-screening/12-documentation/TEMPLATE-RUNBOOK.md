# RUNBOOK: <AlertName>

**Last verified:** YYYY-MM-DD by @<author>
**Severity:** SEV3 / SEV2 / SEV1
**Owner team:** infra / platform / app

## Симптом

Что показывает алёрт. Скриншот / запрос в Prom / Loki.

## Импакт

Что не работает с точки зрения пользователя. Если ничего — снизь severity или удали runbook.

## Первые 5 минут (триаж)

```bash
ssh <host>
top
journalctl -p err -b
docker ps --filter status=exited
```

Что искать: …

## Типовые причины и фиксы

### Причина 1: <короткое название>

Признаки: …

Фикс:
```bash
sudo systemctl restart <service>
```

### Причина 2: <короткое название>

Признаки: …

Фикс:
```bash
docker compose up -d --force-recreate <service>
```

## Когда эскалировать

- Если за 15 минут симптом не ушёл — пишем lead'у в #ops-help.
- Если есть data loss / security impact — сразу SEV1, см. отдельный playbook.

## После инцидента

- Открыть тикет «<AlertName>: что починили».
- Если повторяется — postmortem обязателен.
