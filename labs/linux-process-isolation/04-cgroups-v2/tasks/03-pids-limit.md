# 03 — Лимит числа процессов (pids.max)

## Задача
Поставить `pids.max=5` и убедиться, что `fork` отказывает (`EAGAIN`) при попытке
создать больше процессов — защита от fork-бомб.

## Проверка
```bash
CG=/sys/fs/cgroup
sudo mkdir -p $CG/lab && echo '+pids' | sudo tee $CG/lab/cgroup.subtree_control
sudo mkdir -p $CG/lab/pids
echo 5 | sudo tee $CG/lab/pids/pids.max
sudo sh -c 'echo $$ > '$CG'/lab/pids/cgroup.procs; for i in $(seq 1 10); do sleep 20 & done; wait'
# счётчики читаем СНАРУЖИ (внутри fork для подстановки тоже не сработает):
cat $CG/lab/pids/pids.current
```

## Ожидаемый результат
```
bash: fork: retry: Resource temporarily unavailable
bash: fork: retry: Resource temporarily unavailable
bash: fork: retry: Resource temporarily unavailable
bash: fork: retry: Resource temporarily unavailable
bash: fork: Resource temporarily unavailable
```
А `pids.current` снаружи показывает `5` — больше пяти процессов в группе не создать.
`fork()` возвращает `EAGAIN` — это и есть `--pids-limit` у Docker.
