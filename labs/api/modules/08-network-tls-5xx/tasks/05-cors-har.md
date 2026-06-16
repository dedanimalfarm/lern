# 05 — «Мониторинг зелёный, а пользователю плохо»: CORS, HAR, GraphQL

Объединяющая тема трёх частей (4, 10, 11): **отказ, которого не видно по
HTTP-коду**. curl говорит «200», мониторинг зелёный — а в браузере не
работает. L2 обязан уметь это ловить.

## Часть А: CORS — воспроизвести и починить

1. Убедитесь, что на дефолтном стенде кросс-доменный ответ **не размечен**
   для браузера (нет `Access-Control-Allow-Origin`), хотя curl получает 200.
2. Поднимите стенд с разрешённым origin и покажите, что заголовок появился.
3. Запишите вердикт инцидента + строку с появившимся заголовком в
   `/tmp/api-lab/m08-cors.txt`.

```bash
B=localhost:8080
# дефолт: ответ есть (200), но ACAO нет -> браузер заблокирует
curl -s -i -H 'Origin: https://portal.corp.example' $B/api/v1/tickets | grep -ic access-control
# 0   <- ни одного Access-Control-* -> для скрипта (curl) ок, для браузера нет

# фикс на стороне API: разрешить origin
CORS_ORIGIN='https://portal.corp.example' scripts/api.sh up >/dev/null
curl -s -i -H 'Origin: https://portal.corp.example' $B/api/v1/tickets \
  | grep -i 'access-control-allow-origin' | tr -d '\r' | tee -a /tmp/api-lab/m08-cors.txt
# Access-Control-Allow-Origin: https://portal.corp.example

scripts/api.sh up >/dev/null    # вернуть дефолт (CORS выключен)
```

В `m08-cors.txt` добавьте своими словами вердикт: **сервер работает, дело в
CORS** — на стороне API не хватает `Access-Control-Allow-Origin` для нужного
origin; это правка конфигурации API/прокси, а не «у вас браузер кривой».

## Часть Б: HAR + ловушка GraphQL

Пользователь прислал `assets/incident.har`. Поставьте диагноз **только по
нему** и запишите в `/tmp/api-lab/m08-har.txt`:

```bash
HAR=modules/08-network-tls-5xx/assets/incident.har
jq -r '.log.entries[] | "\(.request.method) \(.request.url) -> \(.response.status) \(.response._error // "")"' "$HAR"
# GET  .../tickets?status=open -> 200
# POST .../tickets             -> 0 net::ERR_FAILED
```

В `m08-har.txt` зафиксируйте: GET (простой запрос) прошёл `200`, а POST
(не-простой: JSON + `Authorization` + кросс-доменный `Origin`) — `status 0`,
`net::ERR_FAILED`. Это **заблокированный CORS-preflight** (часть 4), а не
ошибка приложения. Сервер «работает».

Бонус — та же мысль в GraphQL: ошибка приходит **в `200 OK`**, мониторинг
по кодам её не видит:

```bash
jq '{data, errors}' modules/08-network-tls-5xx/assets/graphql-response.json
# data.ticket == null, а в errors[0].extensions.code == "NOT_FOUND" при HTTP 200
```

## Проверка
```bash
grep -i 'access-control-allow-origin' /tmp/api-lab/m08-cors.txt
grep -iE 'cors|preflight|ERR_FAILED|status 0' /tmp/api-lab/m08-har.txt
```

## Ожидаемый результат
`m08-cors.txt` содержит появившийся `Access-Control-Allow-Origin` и вердикт
«дело в CORS»; `m08-har.txt` — диагноз «заблокированный CORS-preflight для
POST». Стенд возвращён в дефолт (`scripts/api.sh up`).
