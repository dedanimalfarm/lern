# 01 — Загрузить enforce-профиль и заблокировать root

## Задача
Загрузить AppArmor-профиль для `secret-reader.sh` в режиме enforce и убедиться,
что процесс с `uid 0` получает `Permission denied` на запрещённые профилем пути.

> ⚠️ Только на хосте с включённым AppArmor (на WSL2 пропусти — `enabled`=N).

## Проверка
```bash
sudo install -m0755 ./07-apparmor/secret-reader.sh /usr/local/bin/secret-reader.sh
sudo cp ./07-apparmor/profile.aa /etc/apparmor.d/usr.local.bin.secret-reader.sh
sudo apparmor_parser -r /etc/apparmor.d/usr.local.bin.secret-reader.sh
sudo /usr/local/bin/secret-reader.sh
```

## Ожидаемый результат
```
uid: 0
READ_PASSWD: DENIED     # /etc/passwd запрещён (deny), хотя мы root
WRITE_VARLOG: DENIED    # /var/log не разрешён (неявный запрет)
WRITE_TMP: OK           # /tmp разрешён явно (/tmp/** rw)
```
Сравните: без профиля все три были бы `OK`. Профиль ограничил root — это MAC.
Уборка: `sudo apparmor_parser -R /etc/apparmor.d/usr.local.bin.secret-reader.sh`.
