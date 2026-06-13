# 02 — «root» внутри = обычный uid снаружи

## Задача
Доказать ключевое свойство rootless: файл, созданный «root-ом» внутри user-ns, на
хосте принадлежит непривилегированному пользователю, а не настоящему root.

## Проверка
```bash
su -s /bin/sh nobody -c 'unshare --user --map-root-user sh -c "touch /tmp/rootless-test"'
stat -c '%U (uid %u)' /tmp/rootless-test
su -s /bin/sh nobody -c 'unshare --user --map-root-user cat /proc/self/uid_map'
rm -f /tmp/rootless-test
```

## Ожидаемый результат
```
nobody (uid 65534)        # файл создал «root» внутри, а владелец на хосте — nobody
         0      65534          1     # uid 0 внутри ↔ 65534 (nobody) снаружи, диапазон 1
```
Что бы «root» в rootless-контейнере ни делал с файлами, на хосте владелец —
непривилегированный пользователь. Это и есть гарантия безопасности: побег из
такого контейнера НЕ даёт root на хосте.
