# 01 — Токен-флоу и разбор JWT

## Задача
1. Получить токен агента (`support/support123`) и сохранить его (одной
   строкой, без кавычек) в `/tmp/api-lab/m05-token.txt`.
2. Декодировать payload токена и сохранить в
   `/tmp/api-lab/m05-jwt-payload.json` (валидный JSON с `sub`, `role`,
   `iat`, `exp`).
3. Создать этим токеном тикет с подстрокой `m05` в title.

## Проверка
```bash
tr -cd '.' < /tmp/api-lab/m05-token.txt | wc -c        # 2 (три части)
jq '.sub, .exp' /tmp/api-lab/m05-jwt-payload.json
curl -s -H "Authorization: Bearer $(cat /tmp/api-lab/m05-token.txt)" \
  'http://localhost:8080/api/v1/tickets?q=m05' | jq '.total'   # >= 1
```

## Ожидаемый результат
Токен в файле валиден; payload читается; тикет m05 создан.
