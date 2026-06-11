# 02 — Заявка через API: от создания до Done

## Задача
1. Создать минимум ДВЕ заявки через API (servicedeskapi или /rest/api/3 —
   на выбор), навесить на обе метку `api-lab`.
2. Одну заявку провести по workflow до статуса категории **Done**
   (через GET transitions → POST transition), добавив комментарий (ADF).
3. Найти обе JQL'ем: `project = SUP AND labels = api-lab`.

## Проверка
```bash
source ~/.config/api-lab/jira.env
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -G "$JIRA_BASE_URL/rest/api/3/search/jql" \
  --data-urlencode "jql=project = $JIRA_PROJECT AND labels = api-lab" \
  --data-urlencode 'fields=summary,status' \
  | jq '[.issues[] | {key, cat: .fields.status.statusCategory.key}]'
```

## Ожидаемый результат
Минимум две задачи с меткой; минимум у одной `cat == "done"`.
