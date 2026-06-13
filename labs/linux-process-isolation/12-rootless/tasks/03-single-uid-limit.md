# 03 — Ограничение single-uid маппинга

## Задача
Увидеть предел простого rootless (`-r`): внутри отображён РОВНО один uid (твой → 0),
поэтому операции с другими uid (например `chown 1000`) не работают.

## Проверка
```bash
su -s /bin/sh nobody -c 'unshare --user --map-root-user sh -c "touch /tmp/x; chown 1000 /tmp/x"'
rm -f /tmp/x
```

## Ожидаемый результат
```
chown: changing ownership of '/tmp/x': Invalid argument    # uid 1000 НЕ в маппинге
```
`--map-root-user` отображает только один uid. uid 1000 внутри «не существует» →
`chown` падает. Для контейнеров с несколькими пользователями нужен ДИАПАЗОН uid:
запись в `/etc/subuid` (`user:100000:65536`) + setuid-утилиты `newuidmap`/`newgidmap`
(пакет `uidmap`). Их и используют podman и rootless Docker.
