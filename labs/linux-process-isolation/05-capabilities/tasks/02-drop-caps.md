# 02 — Запустить процесс с минимальным набором привилегий

## Задача
Запустить процесс от `nobody` ровно с ОДНОЙ привилегией (`CAP_CHOWN` через
ambient) и убедиться: разрешённая операция работает, а требующая другой
привилегии (`mount` ← `CAP_SYS_ADMIN`) — нет.

## Проверка
```bash
# убрать привилегию из bounding set (её не будет и у потомков)
capsh --drop=cap_net_bind_service --print | sed -n 's/^Bounding set =//p' | grep -o cap_net_bind_service
# (пусто)

# nobody ровно с cap_chown
sudo capsh --keep=1 --user=nobody --inh=cap_chown --addamb=cap_chown -- -c '
  grep CapEff /proc/self/status
  touch /tmp/d && chown root /tmp/d && echo "chown → OK"
  mount -t tmpfs none /mnt 2>&1 | head -1
'
```

## Ожидаемый результат
```
uid=65534  CapEff:	0000000000000001     # ровно одна привилегия (cap_chown)
chown → OK                                  # cap_chown действует
mount: /mnt: must be superuser to use mount # CAP_SYS_ADMIN нет → запрет
```
Процесс — не root, но с одной точечной привилегией. `capsh --decode=0000000000000001`
подтверждает: бит 0 = `cap_chown`. Это и есть принцип наименьших привилегий.
