# Сценарий 01: внутри user-ns ты НЕ root — забыт `--map-root-user`

## Симптом
Создали user namespace, ожидаем быть root внутри — а `id` показывает 65534, и
root-операции падают.
```bash
sudo ./broken/scenario-01/make-broken.sh
# uid внутри (без -r): 65534
# mount: /mnt: must be superuser to use mount.
```

## Подсказки
1. Какой флаг отображает твой uid в 0 внутри user namespace?
2. Кто ты внутри user-ns, если маппинг uid не задан?
3. Почему `mount` падает, хотя внутри user-ns обычно есть capabilities?

## Диагностика
`unshare --user` без `--map-root-user` создаёт user-ns, но НЕ отображает твой uid в
0. Без записи в `uid_map` ядро показывает тебе «overflow uid» (65534/nobody), и ты
не являешься uid 0 в этом namespace → нет capabilities для root-операций → `mount`
(нужен CAP_SYS_ADMIN, которого у nobody нет) падает «must be superuser».

## Решение
Добавить `--map-root-user` (`-r`) — он запишет `uid_map` = `0 <host_uid> 1` (см.
`solutions/01-map-root/fix.sh`):
```bash
sudo ./solutions/01-map-root/fix.sh
# uid внутри (с -r): 0
# MOUNT_OK
```

## Профилактика
- Для «root внутри» всегда `unshare --user --map-root-user` (или `-U -r`).
- Проверка: `unshare -U -r cat /proc/self/uid_map` должно показать `0 <host_uid> 1`;
  `id -u` внутри = 0.
- Помни: capabilities внутри user-ns появляются только у отображённого uid 0 — без
  маппинга ты неотображённый nobody без прав.
