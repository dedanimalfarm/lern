# Решение scenario-01: сделать `new_root` точкой монтирования

`pivot_root` требует, чтобы `new_root` был отдельным mount point. Два способа:

```bash
mount -t tmpfs none /path/newroot          # А: tmpfs (чистая отдельная ФС)
mount --bind /path/newroot /path/newroot   # Б: bind каталога самого на себя
```

```bash
sudo 03-pivot-root/broken/scenario-01/make-broken.sh     # воспроизвести EBUSY
sudo 03-pivot-root/solutions/01-make-mountpoint/fix.sh    # tmpfs → pivot_root OK
```

Ожидаемый итог: `pivot_root OK` и `old_root отмонтирован`. Именно поэтому `runc`
сначала делает `mount(merged, merged, MS_BIND)`, а уже потом `pivot_root`.
