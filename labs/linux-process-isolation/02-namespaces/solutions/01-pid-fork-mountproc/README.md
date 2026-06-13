# Решение scenario-01: триада `--pid --fork --mount-proc`

Корректный PID-namespace требует трёх флагов вместе:
- `--pid` — создать PID namespace;
- `--fork` — запустить команду ПОТОМКОМ (он становится PID 1; без этого сам
  `unshare` остаётся в старом ns со своим хостовым PID);
- `--mount-proc` — поднять mount-ns и перемонтировать `/proc`, чтобы он отражал
  новый pid-ns (иначе `ps` читает хостовый `/proc` и падает «lookup self»).

```bash
sudo 02-namespaces/broken/scenario-01/make-broken.sh        # воспроизвести
sudo 02-namespaces/solutions/01-pid-fork-mountproc/fix.sh    # починить
```

Ожидаемый итог: `$$=1`, `ps -e` показывает только процессы своего namespace.
