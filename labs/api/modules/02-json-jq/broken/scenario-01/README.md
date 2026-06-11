# Сценарий 01: интеграция CRM шлёт битое тело запроса

**Симптом:** после обновления CRM заявки перестали попадать в Helpdesk.
API отвечает `400 invalid_json`. Тело, которое отправляет интеграция,
сохранено в `payload.json`.

В файле **три ошибки формата JSON**. Чините итеративно: валидатор после
каждой правки.

```bash
cp payload.json /tmp/api-lab/m02-payload.json
python3 -m json.tool /tmp/api-lab/m02-payload.json
# правка -> снова валидатор -> ...
```

<details>
<summary>Подсказка 1</summary>

Первое сообщение парсера укажет на строку с `//`. В JSON нет комментариев —
вообще никаких (`//`, `#`, `/* */`). То, что VS Code подсвечивает их в
`settings.json`, — это формат JSONC, не JSON.
</details>

<details>
<summary>Подсказка 2</summary>

`Expecting property name enclosed in double quotes` на строке с `title`:
значение взято в одинарные кавычки. JSON признаёт только двойные.
</details>

<details>
<summary>Подсказка 3</summary>

`Illegal trailing comma` — запятая после ПОСЛЕДНЕГО элемента объекта.
В JSON запятая только МЕЖДУ элементами.
</details>

## Критерий успеха

```bash
python3 -m json.tool /tmp/api-lab/m02-payload.json >/dev/null && echo VALID
# VALID
curl -s -X POST http://localhost:8080/api/v1/tickets \
  -H 'Content-Type: application/json' -d @/tmp/api-lab/m02-payload.json | jq '{id, title}'
# {"id":NN,"title":"Импорт из CRM: не работает выгрузка"}
```

Эталон: `../../solutions/01-payload/payload.json`.
