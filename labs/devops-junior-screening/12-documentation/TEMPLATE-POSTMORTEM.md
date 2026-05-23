# Postmortem: <Short incident name>

- **Date of incident:** YYYY-MM-DD HH:MM UTC
- **Duration:** Xh Ym (MTTD: …, MTTR: …)
- **Severity:** SEV1 / SEV2 / SEV3
- **Authors:** @author1, @author2
- **Status:** draft | reviewed | closed

## Summary

3–5 предложений: что случилось, кого это задело, как починили.

## Impact

- Сколько пользователей.
- Какие сервисы / endpoints.
- Финансовый / репутационный.
- SLO budget burned.

## Timeline (UTC)

| Время  | Событие                                              |
|--------|------------------------------------------------------|
| HH:MM  | Alert <X> fired in #ops-alerts                       |
| HH:MM  | On-call acked, started triage                        |
| HH:MM  | Identified root cause as <…>                         |
| HH:MM  | Mitigation rolled out                                |
| HH:MM  | Alerts cleared, service healthy                      |
| HH:MM  | Incident closed                                      |

## Root cause

Что **на самом деле** пошло не так. Это **не** «нажал не туда» — это «процесс/архитектура позволили нажать не туда без safety net».

Применить **5 Whys** (минимум 3):

1. Q: Почему упало?  A: …
2. Q: Почему это смогло произойти?  A: …
3. Q: Почему мы не поймали раньше?  A: …

## What went well

Не для красоты — это закрепляет паттерны, которые работают.

## What went wrong

Список — что замедлило detection / response.

## Action items

| ID | Action                                          | Owner   | Due        | Ticket |
|----|-------------------------------------------------|---------|------------|--------|
| 1  | Добавить pre-flight check в Ansible-роль ufw    | @author | 2026-06-01 | INFRA-123 |
| 2  | Runbook: добавить «как восстановиться через EC2 console» | @user2 | 2026-05-30 | INFRA-124 |

**Все** action items должны иметь владельца и дату. Без — не считается.

## Lessons learned

1–3 ключевых вывода для команды.
