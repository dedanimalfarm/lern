# 02 — Лимит памяти и OOM-kill

## Задача
Поставить `memory.max=50M`, запретить swap и поймать OOM-kill при попытке занять
больше памяти. Подтвердить по `memory.events`.

## Проверка
```bash
CG=/sys/fs/cgroup
sudo mkdir -p $CG/lab && echo '+memory' | sudo tee $CG/lab/cgroup.subtree_control
sudo mkdir -p $CG/lab/mem
echo 50M | sudo tee $CG/lab/mem/memory.max
echo 0   | sudo tee $CG/lab/mem/memory.swap.max
# просим занять 200M в лимите 50M
sudo sh -c 'echo $$ > '$CG'/lab/mem/cgroup.procs; exec stress-ng --vm 1 --vm-bytes 200M --vm-keep --timeout 6s' 2>&1 | tail -2
cat $CG/lab/mem/memory.events
# (нет stress-ng → exec tail /dev/zero — будет «Killed», код 137)
```

## Ожидаемый результат
```
max 2400
oom 62
oom_kill 62       # OOM-killer убивал воркеры при выходе за 50M
```
А `tail /dev/zero` в этой группе завершается строкой `Killed` (код 137 = 128+SIGKILL).
Ядро не дало процессу выйти за `memory.max`.
