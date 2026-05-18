# Урок 10: DNS — почему «сеть лежит», но это не сеть

## Цель
Понять, что приложение «не видит хост», когда сама сеть в порядке —
сломался DNS. Научиться отличать «нет коннекта» от «не резолвится».

## Основные команды
- `getent hosts <host>` — резолв через ту же логику, что и приложения (учитывает `/etc/nsswitch.conf`, `/etc/hosts`, NSS-плагины).
- `dig <host>` / `dig +short <host>` / `dig @8.8.8.8 <host>` — обращение к конкретному DNS-серверу в обход системного резолвера.
- `nslookup <host>` — простой вариант `dig`, бывает полезен на минимальных образах.
- `resolvectl status` / `resolvectl query <host>` — состояние systemd-resolved (Ubuntu 18.04+).
- `cat /etc/resolv.conf` — какой DNS-сервер используется. В systemd-resolved это часто симлинк на `127.0.0.53`.
- `cat /etc/nsswitch.conf | grep hosts` — порядок: `files dns` означает «сначала `/etc/hosts`, потом DNS».
- `tcpdump -i any -n port 53` — посмотреть реальные DNS-запросы на проводе.

## Типичные грабли
- **`/etc/hosts` перекрывает DNS** — кто-то прописал старый IP, и хост резолвится в него, игнорируя реальный DNS.
- **`search`-домен в `/etc/resolv.conf`** — `curl api` ищет `api.search-domain.local` раньше, чем `api`.
- **systemd-resolved кеширует** — DNS поменялся, но `127.0.0.53` отдаёт старое значение. Сбросить: `sudo resolvectl flush-caches`.
- **`getent` и `dig` дают разное** — DNS работает, но `nsswitch.conf` ходит сначала в `/etc/hosts`, где стоит мусор.

## Задание
1. Запустите `./simulate.sh`. Скрипт «сломает» резолв `github.com` — добавит липовую запись в `/etc/hosts`.
2. Попробуйте `curl -I https://github.com` — увидите connection failed / wrong cert / зависание.
3. Сравните:
   - `dig +short github.com` (идёт в DNS напрямую) → правильный IP.
   - `getent hosts github.com` (как делают приложения) → подложный IP.
4. Найдите запись в `/etc/hosts` и удалите её. Проверьте `getent hosts github.com` снова — должно стать как `dig`.
5. Бонус: запустите `tcpdump -i any -n port 53` в одном терминале и `getent hosts example.com` в другом — увидите живой DNS-запрос.

## Очистка
`./simulate.sh` сам не чистит — отредактируйте `/etc/hosts` руками (последняя строка с `github.com`).
