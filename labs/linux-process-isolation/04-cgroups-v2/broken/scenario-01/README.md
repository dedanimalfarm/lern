# Сценарий 01: в дочерней cgroup нет `cpu.max` — лимит некуда записать

## Симптом
Создали cgroup, хотим задать `cpu.max` — а файла нет, и запись отказывает.
```bash
sudo ./broken/scenario-01/make-broken.sh
# subtree_control родителя (пусто по умолчанию): ''
# файлы 'cpu*' в дочерней (НЕТ cpu.max):
#   cpu.pressure
#   cpu.stat
# пытаемся задать лимит:
# sh: 1: cannot create /sys/fs/cgroup/lpi-parent/child/cpu.max: Permission denied
#   exit=2
```

## Подсказки
1. Какое правило управляет тем, какие файлы лимитов появляются в дочерней cgroup?
2. Посмотри `cat /sys/fs/cgroup/lpi-parent/cgroup.subtree_control` — что там?
3. Где включается контроллер `cpu` — в самой группе или у её родителя?

## Диагностика
В cgroup v2 контроллеры включаются **сверху вниз**: файл лимита `cpu.max`
появляется в дочерней cgroup, только если контроллер `cpu` делегирован ей через
`cgroup.subtree_control` **родителя**. У нас `subtree_control` родителя пуст —
поэтому в `child` есть лишь read-only `cpu.stat`/`cpu.pressure`, но НЕТ `cpu.max`.
Запись в несуществующий контрол-файл cgroupfs отвергает (`Permission denied`).

## Решение
Включить `cpu` в `subtree_control` РОДИТЕЛЯ (см. `solutions/01-enable-subtree-control/fix.sh`):
```bash
sudo ./solutions/01-enable-subtree-control/fix.sh
# subtree_control = 'cpu'
# теперь в дочерней есть: cpu.max
#   лимит задан: cpu.max = 50000 100000
```

## Профилактика
- Перед установкой любого лимита проверь, что контроллер делегирован:
  `echo '+cpu +memory +pids' > <родитель>/cgroup.subtree_control`.
- Помни про «no internal processes»: контроллеры включают на узлах-родителях
  (без процессов), а лимиты вешают на листовые подгруппы (с процессами).
- Признак готовности дочерней группы: в ней появились `cpu.max`/`memory.max`/`pids.max`.
