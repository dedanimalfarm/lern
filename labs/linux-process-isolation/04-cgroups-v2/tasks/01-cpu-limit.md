# 01 — Лимит CPU и троттлинг

## Задача
Ограничить процесс 20% одного ядра через `cpu.max` и доказать срабатывание лимита
по счётчикам `cpu.stat` (`nr_throttled`, `throttled_usec`).

## Проверка
```bash
CG=/sys/fs/cgroup
sudo mkdir -p $CG/lab && echo '+cpu' | sudo tee $CG/lab/cgroup.subtree_control
sudo mkdir -p $CG/lab/cpu
echo "20000 100000" | sudo tee $CG/lab/cpu/cpu.max          # 20% одного ядра
sudo sh -c 'echo $$ > '$CG'/lab/cpu/cgroup.procs; exec stress-ng --cpu 1 --timeout 5s' >/dev/null 2>&1
cat $CG/lab/cpu/cpu.stat
# (нет stress-ng → exec timeout 5 bash -c "while :; do :; done")
```

## Ожидаемый результат
```
usage_usec 1013841      # за 5с потрачено ~1.01с CPU = ~20% одного ядра
nr_periods 51
nr_throttled 50         # тормозили почти каждый период
throttled_usec 3990012  # ~3.99с суммарно простояли в throttle
```
Воркер хотел 100% ядра, но `cpu.max` удержал его на 20%. Уборка:
`for p in $(cat $CG/lab/cpu/cgroup.procs); do echo $p|sudo tee $CG/cgroup.procs; done; sudo rmdir $CG/lab/cpu`.
