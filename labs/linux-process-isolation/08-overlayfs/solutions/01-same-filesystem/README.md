# Решение scenario-01: workdir и upperdir на одной ФС

overlay делает CoW через атомарный `rename()` из `workdir` в `upperdir`, а
`rename(2)` между разными ФС невозможен (`EXDEV`). Значит `workdir` и `upperdir`
обязаны быть на одной файловой системе:

```bash
B=/lab/ovl; mkdir -p $B/{lower,upper,work,merged}   # всё под одним корнем = одна ФС
mount -t overlay overlay -o "lowerdir=$B/lower,upperdir=$B/upper,workdir=$B/work" $B/merged
```

```bash
sudo 08-overlayfs/broken/scenario-01/make-broken.sh    # work на tmpfs → mount падает
sudo 08-overlayfs/solutions/01-same-filesystem/fix.sh    # work на той же ФС → mount OK
```

Docker соблюдает это автоматически: `lowerdir`/`upperdir`/`workdir` лежат рядом в
`/var/lib/docker/overlay2/<id>/`. При невнятной ошибке `mount` смотри `dmesg | tail`.
