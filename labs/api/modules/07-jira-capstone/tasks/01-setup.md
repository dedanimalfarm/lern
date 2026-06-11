# 01 — Стенд Atlassian и реквизиты

## Задача
1. Зарегистрировать бесплатный сайт `*.atlassian.net`, создать проект
   Service Management с ключом `SUP`.
2. Выпустить API-токен `api-lab`.
3. Заполнить `~/.config/api-lab/jira.env` (права 600) переменными
   `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`, `JIRA_PROJECT`.

## Проверка
```bash
source ~/.config/api-lab/jira.env
stat -c '%a' ~/.config/api-lab/jira.env        # 600
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$JIRA_BASE_URL/rest/api/3/myself" \
  | jq -r '.displayName'
```

## Ожидаемый результат
`myself` возвращает 200 с вашим displayName; файл с реквизитами защищён.
