# CLAUDE.md — labs/api

Курс «Работа с API» для подготовки к L2-поддержке. План и карта модулей —
в `README.md`.

## Стенд

- Учебный сервер: `common/server/helpdesk_api.py` — ТОЛЬКО стандартная
  библиотека Python, никаких pip-зависимостей. Управление —
  `scripts/api.sh up|down|status|logs|sink-up|sink-down`.
- Конфигурация сервера — через env (`AUTH_MODE`, `RATE_LIMIT`, `FAULT`,
  `WEBHOOK_URL`, `TOKEN_TTL`, `CORS_ORIGIN`, `TLS_CERT`/`TLS_KEY`…); поломки
  (`slow`/`error500`/`badjson`/`wrongct`/`error502`/`error503`/`error504`/
  `flaky`) переключаются на лету через `POST /api/v1/_lab/fault`, состояние —
  `GET /api/v1/_lab/state`, пересев данных — `POST /api/v1/_lab/reset`.
  HTTPS-стенд (самоподпись, :8443) — `scripts/api.sh tls-up|tls-down`.
- Сид-данные детерминированы (8 тикетов, id 1–8) — «ожидаемые выводы»
  в README модулей рассчитаны на состояние после `_lab/reset`.
- Модуль 07 — внешний SaaS (Jira Cloud free). Его «ожидаемые выводы» —
  ПРИМЕРНЫЕ (помечено в README модуля), verify работает через env
  `JIRA_BASE_URL`/`JIRA_EMAIL`/`JIRA_API_TOKEN`.

## Правила контента модулей

- Эталон формата — `labs/kubernetes/modules/29-*`: README с `<!-- TOC -->`,
  строка «⏱ время · сложность · пререквизиты», теория перед каждой частью,
  контрольные вопросы после части, `tasks/*.md`, `broken/scenario-XX/` +
  `solutions/`, `verify/{prepare.sh,verify.sh,cleanup.sh}`, шпаргалка,
  итоговые вопросы, «Чему вы научились».
- «Ожидаемые выводы» модулей 01–06 и 08 ОБЯЗАТЕЛЬНО снимаются с живого стенда.
- Каждый модуль самодостаточен: prepare.sh сам поднимает стенд в нужном
  режиме, cleanup.sh возвращает дефолт (`scripts/api.sh up` без env).
- Ориентация на трудоустройство: в каждом модуле есть блок «Как это звучит
  на собеседовании» либо вопросы, сформулированные как интервью-вопросы.

## QA-контракт

- Прогон модуля: `bash verify/prepare.sh && bash verify/verify.sh;
  bash verify/cleanup.sh`.
- В verify-скриптах под `set -euo pipefail` подстановки с grep/jq
  заканчивать `|| true` (грабли из k8s-labs: пустой grep молча убивает
  скрипт до fail()).
- Общие функции — `scripts/verify/helpers.sh` (ok/fail/need_bin/http_code/
  require_api_up/require_http/require_jq/require_jq_min/
  require_valid_json_file).
- Перед коммитом: shellcheck по всем `*.sh`, `python3 -m json.tool` по всем
  JSON-артефактам (Postman-коллекции!), YAML — `yaml.safe_load`.

## Git

- Коммиты semantic + scope: `feat(api-labs):`, `fix(api-m03):`,
  тело на русском, атомарные.
