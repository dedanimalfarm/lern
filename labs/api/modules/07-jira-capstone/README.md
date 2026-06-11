# Лабораторная работа 07 (capstone): Jira Service Management Cloud API

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Часть 1: Свой стенд в облаке Atlassian](#часть-1-свой-стенд-в-облаке-atlassian)
  - [1.1 Сайт и проект](#11-сайт-и-проект)
  - [1.2 API-токен и файл окружения](#12-api-токен-и-файл-окружения)
- [Часть 2: Аутентификация и первый запрос](#часть-2-аутентификация-и-первый-запрос)
- [Часть 3: Настоящая документация](#часть-3-настоящая-документация)
- [Часть 4: Тикеты через API](#часть-4-тикеты-через-api)
  - [4.1 Создать заявку](#41-создать-заявку)
  - [4.2 Метка, комментарий](#42-метка-комментарий)
  - [4.3 Workflow: transitions](#43-workflow-transitions)
  - [4.4 Поиск: JQL](#44-поиск-jql)
- [Часть 5: Postman и Jira](#часть-5-postman-и-jira)
- [Часть 6: Отчёт смены одной командой](#часть-6-отчёт-смены-одной-командой)
- [Broken-сценарий: скрипт «из старой вики» против живой Jira](#broken-сценарий-скрипт-из-старой-вики-против-живой-jira)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта артефактов модуля](#финальная-карта-артефактов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
- [Чему вы научились](#чему-вы-научились)
- [Что положить в резюме](#что-положить-в-резюме)
<!-- /TOC -->

> ⏱ время ~120 мин · сложность 3/5 · пререквизиты: модули 01–06; интернет,
> почта для аккаунта Atlassian

Цель: применить все навыки курса к **настоящей** системе — Jira Service
Management (самое частое имя в вакансиях L2). Вы сами развернёте облачный
стенд, получите токен, разберётесь в чужой документации и проведёте заявку
через workflow — только через API.

> ⚠️ **Об «ожидаемых выводах».** Это SaaS: ваши URL, id и ключи будут
> другими, а Atlassian регулярно меняет детали API. Все выводы в этом
> модуле — **примерные** (структура верна, значения ваши). Если запрос
> отвечает не так, как написано, — главный навык модуля 03: идите в
> актуальную документацию.

---

## Предварительные требования

```bash
which curl jq python3
# интернет до *.atlassian.net и *.atlassian.com
```

---

## Часть 1: Свой стенд в облаке Atlassian

### Теория для изучения перед частью

- **Jira Service Management (JSM)** — тикет-система Atlassian поверх
  платформы Jira. Free-план: до 3 агентов — достаточно для лаборатории
  и портфолио.
- У Jira Cloud **два REST API**, оба пригодятся:
  - **Platform API** `/rest/api/3/…` — issues, поиск (JQL), комментарии,
    переходы — общий для всех Jira-продуктов;
  - **Service Desk API** `/rest/servicedeskapi/…` — то, что специфично
    для JSM: заявки клиентов (customer requests), очереди, SLA.
- **Аутентификация для скриптов — Basic: email + API-токен** (НЕ пароль:
  пароль для API отключён). Это ровно схема из модуля 05, только в роли
  пароля — длинный токен.

---

### 1.1 Сайт и проект

1. Зарегистрируйте бесплатный сайт: <https://www.atlassian.com/software/jira/service-management/free>
   → получите `https://<ваше-имя>.atlassian.net`.
2. Создайте проект: тип **Service Management**, шаблон **IT service
   management**, имя `Support`, ключ **SUP** (ключ важен — он во всех
   ссылках и JQL).
3. Откройте проект в браузере, создайте одну заявку руками — будет с чем
   сравнивать API-вид.

### 1.2 API-токен и файл окружения

1. <https://id.atlassian.com/manage-profile/security/api-tokens> →
   **Create API token** → назовите `api-lab` → скопируйте (показывается
   один раз!).
2. Сохраните реквизиты в файл окружения (гигиена секретов — модуль 05;
   файл вне git, права 600):

```bash
mkdir -p ~/.config/api-lab
cat > ~/.config/api-lab/jira.env <<'EOF'
export JIRA_BASE_URL="https://<ваше-имя>.atlassian.net"
export JIRA_EMAIL="<email аккаунта>"
export JIRA_API_TOKEN="<токен>"
export JIRA_PROJECT="SUP"
EOF
chmod 600 ~/.config/api-lab/jira.env
source ~/.config/api-lab/jira.env
```

**Контрольные вопросы:**
1. Почему для API нужен токен, а не пароль аккаунта? Чем токен лучше
   (вспомните жизненный цикл секретов из модуля 05)?
2. Зачем проектный ключ (SUP) и где он встретится?

---

## Часть 2: Аутентификация и первый запрос

```bash
source ~/.config/api-lab/jira.env

# «whoami» Jira: кто я с точки зрения API
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$JIRA_BASE_URL/rest/api/3/myself" \
  | jq '{accountId, displayName, emailAddress}'
# {
#   "accountId": "712020:...",        <- примерный вид; ваши значения другие
#   "displayName": "Ivan Ivanov",
#   "emailAddress": "ivan@example.com"
# }

# Проверка «лестницы» 401: неверный токен
curl -s -o /dev/null -w '%{http_code}\n' \
  -u "$JIRA_EMAIL:wrong-token" "$JIRA_BASE_URL/rest/api/3/myself"
# 401
```

> Если 401 с правильным токеном: чаще всего в `JIRA_EMAIL` не тот адрес
> (нужен email АККАУНТА Atlassian) или токен скопирован с пробелом.
> Диагностика — модуль 05: читайте тело ответа, Jira пишет причину.

**Контрольные вопросы:**
1. Какая схема аутентификации используется и как она выглядит в заголовке?
2. Как быстро проверить валидность реквизитов одной командой?

---

## Часть 3: Настоящая документация

### Теория для изучения перед частью

- Главные доки (закладки на смену):
  - Platform API v3: <https://developer.atlassian.com/cloud/jira/platform/rest/v3/>
  - Service Desk API: <https://developer.atlassian.com/cloud/jira/service-desk/rest/>
- **Особенности, о которых дока предупреждает** (и которые ломают чужие
  скрипты — см. broken-сценарий):
  - **Поиск переехал:** старый `GET /rest/api/3/search` объявлен
    deprecated и отключается; актуальный — `GET /rest/api/3/search/jql`
    с пагинацией через `nextPageToken` (не `startAt`!). Классический
    пример «API эволюционирует, интеграции отстают».
  - **Поле description в Platform API v3 — это не строка**, а документ
    **ADF** (Atlassian Document Format) — JSON-дерево. Plain-строку v3
    не примет (400).
  - В **Service Desk API** же описание заявки — обычная строка
    (`requestFieldValues.description`). Поэтому заявки удобнее создавать
    через него.
- Это живой пример мысли модуля 03: один продукт — два API с разными
  словарями и форматами; что куда — говорит только документация.

**Контрольные вопросы:**
1. Каким эндпоинтом искать задачи в Jira Cloud сегодня и что случилось со
   старым?
2. Что такое ADF и в каком из двух API без него можно обойтись?

---

## Часть 4: Тикеты через API

### 4.1 Создать заявку

```bash
# Каким service desk'ам я могу подавать заявки + их requestType:
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/rest/servicedeskapi/servicedesk" \
  | jq '.values[] | {id, projectKey: .projectKey}'
# {"id":"1","projectKey":"SUP"}

curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/rest/servicedeskapi/servicedesk/1/requesttype" \
  | jq '.values[] | {id, name}'
# {"id":"10006","name":"Get IT help"}     <- ваши id будут другими!
# ...

# Создаём заявку (подставьте СВОИ serviceDeskId/requestTypeId):
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -X POST "$JIRA_BASE_URL/rest/servicedeskapi/request" \
  -H 'Content-Type: application/json' \
  -d '{
    "serviceDeskId": "1",
    "requestTypeId": "10006",
    "requestFieldValues": {
      "summary": "VPN не подключается из дома (api-lab)",
      "description": "Создано через REST API в рамках лабораторной."
    }
  }' | jq '{issueKey: .issueKey, status: .currentStatus.status}'
# {"issueKey":"SUP-2","status":"Waiting for support"}

# Заявка — это issue платформы; смотрим её Platform API:
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/rest/api/3/issue/SUP-2?fields=summary,status,labels" \
  | jq '.fields | {summary, status: .status.name, labels}'
```

### 4.2 Метка, комментарий

```bash
# Метка api-lab — по ней мы будем находить «свои» задачи (и по ней же verify)
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -X PUT "$JIRA_BASE_URL/rest/api/3/issue/SUP-2" \
  -H 'Content-Type: application/json' \
  -d '{"update": {"labels": [{"add": "api-lab"}]}}' \
  -o /dev/null -w '%{http_code}\n'
# 204

# Комментарий в Platform API v3 — уже ADF (вот он, формат из доки):
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -X POST "$JIRA_BASE_URL/rest/api/3/issue/SUP-2/comment" \
  -H 'Content-Type: application/json' \
  -d '{
    "body": {
      "type": "doc", "version": 1,
      "content": [{"type": "paragraph", "content": [
        {"type": "text", "text": "Диагностика начата: проверен curl -v, ответ 200."}
      ]}]
    }
  }' | jq '{id, created}'
```

### 4.3 Workflow: transitions

```bash
# Какие переходы доступны задаче ИЗ ТЕКУЩЕГО статуса:
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/rest/api/3/issue/SUP-2/transitions" \
  | jq '.transitions[] | {id, name, to: .to.name}'
# {"id":"11","name":"In progress","to":"In Progress"}
# {"id":"21","name":"Resolve this issue","to":"Resolved"}   <- имена зависят от workflow

# Перевод задачи = POST с ID перехода (не имени статуса!):
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -X POST "$JIRA_BASE_URL/rest/api/3/issue/SUP-2/transitions" \
  -H 'Content-Type: application/json' \
  -d '{"transition": {"id": "11"}}' \
  -o /dev/null -w '%{http_code}\n'
# 204
```

> Это главное отличие «взрослых» тикет-систем от нашего стенда: статус не
> присваивается напрямую (`PATCH {"status": ...}` тут нет) — задача ХОДИТ
> по workflow переходами, и допустимые переходы зависят от текущего
> статуса. Поэтому алгоритм всегда двухшаговый: GET transitions → POST
> transition.id.

### 4.4 Поиск: JQL

```bash
# JQL — язык запросов Jira; актуальный эндпоинт /search/jql:
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -G \
  "$JIRA_BASE_URL/rest/api/3/search/jql" \
  --data-urlencode 'jql=project = SUP AND labels = api-lab' \
  --data-urlencode 'fields=summary,status' \
  | jq '.issues[] | {key, summary: .fields.summary, status: .fields.status.name}'
# {"key":"SUP-2","summary":"VPN не подключается из дома (api-lab)","status":"In Progress"}
```

**Контрольные вопросы:**
1. Почему заявку создавали через Service Desk API, а метку и переходы —
   через Platform API?
2. Почему нельзя «просто поставить статус Done» и как делается правильно?
3. Напишите JQL: открытые задачи проекта SUP с меткой api-lab, созданные
   за последние сутки. *(подсказка: `created >= -1d`)*
4. Как API сообщит, что вы пытаетесь выполнить недоступный переход?

---

## Часть 5: Postman и Jira

1. Создайте environment `jira-cloud`: `jira_base_url`, `jira_email`,
   `jira_token` (тип **secret** — модуль 05!).
2. Новая коллекция «Jira SM»: на вкладке **Authorization** коллекции
   выберите **Basic Auth**, Username `{{jira_email}}`, Password
   `{{jira_token}}` — все запросы коллекции унаследуют.
3. Перенесите в коллекцию запросы Части 4 (myself, создание заявки,
   transitions, JQL-поиск) и добавьте тесты по образцу модуля 04
   (статус-код + ключевое поле тела).
4. Экспортируйте коллекцию в `/tmp/api-lab/m07-jira-collection.json` —
   артефакт для портфолио (токенов в ней нет — они в environment).

**Контрольные вопросы:**
1. Чем удобна авторизация на уровне коллекции?
2. Почему экспорт коллекции безопасен при правильном разделении
   коллекция/environment?

---

## Часть 6: Отчёт смены одной командой

Соберите скрипт `jira-shift-report.sh` (эталон —
`solutions/02-shift-report/`): сколько задач проекта в каждом статусе +
список «в работе» — всё через `/search/jql` и jq (рецепты модуля 02).

```bash
bash solutions/02-shift-report/jira-shift-report.sh
# === Отчёт смены: проект SUP (2026-06-11T02:00:00Z) ===
# По статусам:
#   Waiting for support  3
#   In Progress          1
#   Resolved             2
# В работе:
#   SUP-2  VPN не подключается из дома (api-lab)
```

---

## Broken-сценарий: скрипт «из старой вики» против живой Jira

`broken/scenario-01/jira-create-and-find.sh` — скрипт 2023 года: создаёт
задачу и ищет свои задачи. На современной Jira Cloud он ломается **двумя**
способами — оба описаны в актуальной документации (и в Части 3).

```bash
source ~/.config/api-lab/jira.env
bash broken/scenario-01/jira-create-and-find.sh
# читайте ответы: Jira подробно объясняет, что не так
```

Подсказки — `broken/scenario-01/README.md`, эталон —
`solutions/01-create-and-find/`.

---

## Проверка модуля

```bash
source ~/.config/api-lab/jira.env
bash verify/prepare.sh    # проверит реквизиты и связность
# ... части 2–6, broken-сценарий ...
bash verify/verify.sh
# [OK] module 07 verified
```

`verify.sh` проверяет (всё — через ВАШ аккаунт): реквизиты валидны
(`/myself` 200) → в проекте есть задачи с меткой `api-lab` (создание через
API) → хотя бы одна из них доведена переходами до категории Done →
экспортирована Postman-коллекция (валидный JSON v2.1 с Basic-auth на
переменных, без вшитого токена).

---

## Финальная карта артефактов модуля

| Артефакт | Где | Что демонстрирует |
|---|---|---|
| сайт `*.atlassian.net` + проект SUP | облако | развёрнутый стенд JSM |
| `~/.config/api-lab/jira.env` (600) | файл | гигиена секретов |
| задачи с меткой `api-lab` | Jira | создание/изменение через API |
| задача в Done | Jira | workflow через transitions |
| `/tmp/api-lab/m07-jira-collection.json` | файл | Postman-коллекция для портфолио |
| `jira-shift-report.sh` | скрипт | JQL + jq: автоматизация смены |

---

## Теоретические вопросы (итоговые)

1. Два REST API Jira Cloud: какие задачи решает каждый и где граница?
2. Опишите аутентификацию скрипта к Jira Cloud и почему пароль не подходит.
3. Что такое ADF, где он обязателен и как выглядит минимальный документ?
4. Чем переходы workflow отличаются от «установки статуса» и как перевести
   задачу через API?
5. Что изменилось в поиске Jira (эндпоинт, пагинация) и чему это учит
   про интеграции вообще?
6. Как организовать поиск «своих» учебных задач, не задевая чужие?
   *(метки + JQL)*

---

## Практические задания (отработка)

1. Разверните сайт + проект SUP, получите токен, заполните `jira.env`.
2. Создайте через API минимум две заявки с меткой `api-lab`.
3. Одну доведите переходами до Done, с комментарием на каждом шаге.
4. Соберите Postman-коллекцию (auth на уровне коллекции) и экспортируйте
   в `/tmp/api-lab/m07-jira-collection.json`.
5. Почините `broken/scenario-01`.
6. Напишите свой вариант отчёта смены (Часть 6) — добавьте разбивку по
   приоритетам.

---

## Шпаргалка

```bash
source ~/.config/api-lab/jira.env
AUTH=(-u "$JIRA_EMAIL:$JIRA_API_TOKEN")

# === Платформа ===
curl -s "${AUTH[@]}" "$JIRA_BASE_URL/rest/api/3/myself"
curl -s "${AUTH[@]}" "$JIRA_BASE_URL/rest/api/3/issue/SUP-2?fields=summary,status,labels"
curl -s "${AUTH[@]}" -X PUT "$JIRA_BASE_URL/rest/api/3/issue/SUP-2" \
  -H 'Content-Type: application/json' -d '{"update":{"labels":[{"add":"api-lab"}]}}'
curl -s "${AUTH[@]}" "$JIRA_BASE_URL/rest/api/3/issue/SUP-2/transitions"          # что доступно
curl -s "${AUTH[@]}" -X POST "$JIRA_BASE_URL/rest/api/3/issue/SUP-2/transitions" \
  -H 'Content-Type: application/json' -d '{"transition":{"id":"11"}}'             # перейти

# === Поиск (актуальный!) ===
curl -s "${AUTH[@]}" -G "$JIRA_BASE_URL/rest/api/3/search/jql" \
  --data-urlencode 'jql=project = SUP AND labels = api-lab' \
  --data-urlencode 'fields=summary,status'

# === Service Desk ===
curl -s "${AUTH[@]}" "$JIRA_BASE_URL/rest/servicedeskapi/servicedesk"
curl -s "${AUTH[@]}" "$JIRA_BASE_URL/rest/servicedeskapi/servicedesk/1/requesttype"
curl -s "${AUTH[@]}" -X POST "$JIRA_BASE_URL/rest/servicedeskapi/request" \
  -H 'Content-Type: application/json' \
  -d '{"serviceDeskId":"1","requestTypeId":"<id>","requestFieldValues":{"summary":"...","description":"..."}}'

# === Минимальный ADF (для description/comment в /rest/api/3) ===
# {"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"..."}]}]}
```

## Чему вы научились

В этом модуле вы научились:
- Разворачивать облачный стенд Jira Service Management с нуля
- Аутентифицироваться к реальному SaaS API (email + API-токен)
- Работать по настоящей документации Atlassian (два API, ADF, JQL)
- Вести задачу по workflow переходами и искать задачи JQL'ем
- Собирать Postman-коллекцию для реальной системы без утечки секретов

## Что положить в резюме

После этого модуля честно писать:

> Опыт работы с REST API (curl, Postman, JSON): интеграция с Jira Service
> Management Cloud — создание и сопровождение заявок через
> /rest/api/3 и /rest/servicedeskapi (JQL, transitions, ADF),
> Postman-коллекции с автотестами, разбор инцидентов интеграций
> (таймауты, 5xx, контрактные ошибки), эскалации по шаблону.

И к собеседованию: 10 вопросов из README курса — у вас теперь на каждый
есть ответ с примером из собственных рук.
