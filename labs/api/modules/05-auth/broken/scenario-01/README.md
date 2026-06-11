# Сценарий 01: скрипт смены ловит 401

**Симптом:** `my-tickets.sh` вместо списка тикетов кладёт в файл ошибку 401.

Диагностика — строго по `error.code` (Часть 3 README, карта кодов в
шпаргалке). Ошибки две, проявляются по очереди.

<details>
<summary>Подсказка 1</summary>

В файле — `{"code":"missing_token"}`: сервер вообще не увидел Bearer-токен.
Посмотрите на заголовок Authorization в скрипте: схема (`Bearer `) перед
токеном отсутствует. `Authorization: <токен>` и
`Authorization: Bearer <токен>` — разные вещи.
</details>

<details>
<summary>Подсказка 2</summary>

Теперь `{"code":"malformed_token"}`. Распечатайте переменную TOKEN —
там `null`. Значит, jq вытащил из ответа `/auth/token` несуществующее
поле. Как называется поле с токеном на самом деле? Посмотрите ответ
эндпоинта руками (или в доке: `POST /api/v1/auth/token`).
</details>

## Критерий успеха

```bash
bash my-tickets.sh
# сохранено в /tmp/api-lab/m05-my-tickets.json:
# {"id":3,"title":"Не приходят письма от Jira"}
# {"id":4,"title":"Ошибка 500 при выгрузке отчёта из CRM"}
jq '.items | length' /tmp/api-lab/m05-my-tickets.json
# 2 (или больше)
```

Эталон: `../../solutions/01-my-tickets/`.
