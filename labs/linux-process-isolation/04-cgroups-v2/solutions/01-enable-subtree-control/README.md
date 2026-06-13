# Решение scenario-01: делегировать контроллер через `subtree_control`

В cgroup v2 контроллеры включаются сверху вниз. Чтобы в дочерней cgroup появился
`cpu.max`, контроллер `cpu` нужно включить в `cgroup.subtree_control` родителя:

```bash
echo '+cpu +memory +pids' > /sys/fs/cgroup/<родитель>/cgroup.subtree_control
```

```bash
sudo 04-cgroups-v2/broken/scenario-01/make-broken.sh           # нет cpu.max → отказ
sudo 04-cgroups-v2/solutions/01-enable-subtree-control/fix.sh   # +cpu → cpu.max появился
```

Ожидаемый итог: в дочерней группе появляется `cpu.max`, и лимит `50000 100000`
успешно записывается. Помни про «no internal processes»: контроллеры — на
родителе-узле, процессы и лимиты — в листовых подгруппах.
