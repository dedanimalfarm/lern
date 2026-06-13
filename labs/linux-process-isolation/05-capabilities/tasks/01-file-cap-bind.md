# 01 — Дать бинарю одну привилегию (bind :80 от nobody)

## Задача
Выдать копии `python3` привилегию `CAP_NET_BIND_SERVICE` через `setcap +ep` и
убедиться, что непривилегированный `nobody` теперь может слушать порт 80 — без
полного root и без SUID.

> ⚠️ Enforcement bind низких портов через file-cap **не работает на WSL2** (там
> привилегия хранится, но не действует). Делай это задание на реальном Linux-хосте.

## Проверка
```bash
PY=/tmp/pyweb; cp "$(command -v python3)" "$PY"
# без привилегии :80 нельзя
su -s /bin/bash nobody -c "$PY -m http.server 80 --bind 127.0.0.1"   # PermissionError
sudo setcap cap_net_bind_service+ep "$PY"; getcap "$PY"
su -s /bin/bash nobody -c "$PY -m http.server 80 --bind 127.0.0.1"   # теперь слушает
sudo setcap -r "$PY"; rm -f "$PY"
```

## Ожидаемый результат
```
getcap: /tmp/pyweb cap_net_bind_service=ep
nobody :80 без cap → PermissionError: [Errno 13] Permission denied
nobody :80 c  +ep  → слушает (BOUND)
nobody :80 после -r → снова PermissionError
```
Одна точечная привилегия открыла ровно одну возможность. Это `--cap-add
NET_BIND_SERVICE` у Docker.
