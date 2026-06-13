# 02 — Режим complain vs enforce

## Задача
Перевести профиль в complain и увидеть, что **неявные** запреты больше не
блокируются (только логируются), а **явные `deny`** — продолжают блокировать.

## Проверка
```bash
# (профиль уже загружен из задания 01)
sudo aa-complain /usr/local/bin/secret-reader.sh
sudo /usr/local/bin/secret-reader.sh        # complain
sudo aa-enforce /usr/local/bin/secret-reader.sh
sudo /usr/local/bin/secret-reader.sh        # снова enforce
```

## Ожидаемый результат
```
# complain:
READ_PASSWD: DENIED     # явный deny /etc/passwd enforce-ится ВСЕГДА
WRITE_VARLOG: OK        # неявный запрет /var/log в complain НЕ блокируется
WRITE_TMP: OK
# enforce:
WRITE_VARLOG: DENIED    # снова блокируется
```
Вывод: complain ослабляет только **неявные** запреты (удобно для отладки нового
профиля через `aa-logprof`), но `deny`-правила остаются жёсткими.
