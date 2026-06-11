# Сценарий 01: скрипт 2023 года против Jira Cloud 2026

**Симптом:** обе половины скрипта (`создать` и `найти`) возвращают ошибки.

Это НАСТОЯЩИЙ класс инцидентов: API эволюционировал, интеграция отстала.
Чините по ответам сервера + актуальной документации Atlassian.

<details>
<summary>Подсказка 1 — создание задачи (400)</summary>

Jira отвечает 400 и в `errors.description` пишет что-то вроде
«Operation value must be an Atlassian Document» / ошибки формата.
В Platform API **v3** поле `description` — не строка, а ADF-документ:

```json
"description": {"type": "doc", "version": 1, "content": [
  {"type": "paragraph", "content": [{"type": "text", "text": "..."}]}]}
```

Альтернатива — создавать заявку через `/rest/servicedeskapi/request`,
где description остаётся строкой (Часть 4.1).
</details>

<details>
<summary>Подсказка 2 — поиск</summary>

Старый `GET /rest/api/3/search` выведен из эксплуатации (Atlassian
отключал его в 2025): в зависимости от сайта вы получите 404/410 или
ответ-заглушку с предупреждением. Актуальный эндпоинт —
`GET /rest/api/3/search/jql` (и пагинация в нём через `nextPageToken`).
Сравните с историей `/api/v0 → /api/v1` из модуля 03 — паттерн тот же.
</details>

## Критерий успеха

```bash
bash jira-create-and-find.sh
# == создаём задачу ==
# {"id":"10023","key":"SUP-7","self":"https://.../rest/api/3/issue/10023"}
# == ищем свои задачи ==
# {"issues":[{"key":"SUP-7","fields":{"summary":"Заявка из скрипта (api-lab)",...
```

Эталон: `../../solutions/01-create-and-find/`.
