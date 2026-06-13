# Решение scenario-01: добавить `--map-root-user` (`-r`)

Без маппинга uid ты внутри user-ns — неотображённый nobody. Флаг `-r` отображает
твой uid хоста в 0 внутри:

```bash
unshare --user --map-root-user id -u        # 0
cat /proc/self/uid_map                        # 0 <host_uid> 1
```

```bash
sudo 12-rootless/broken/scenario-01/make-broken.sh    # без -r → uid 65534, mount запрещён
sudo 12-rootless/solutions/01-map-root/fix.sh           # с -r → uid 0, MOUNT_OK
```

`-r` = single-uid маппинг (твой uid → 0). Для нескольких uid внутри нужен диапазон
`/etc/subuid` + `newuidmap`/`newgidmap` (пакет `uidmap`) — то, что используют
podman и rootless Docker.
