# 01-events-and-conditions

## Задача
Научиться читать таймлайн деградации из events.

## Команды
```bash
kubectl get events -A --sort-by=.lastTimestamp
kubectl -n lab describe pod <pod>
```
## Ожидаемый результат
- В списке events вы нашли для проблемного пода цепочку `Scheduled → Pulling → Pulled →
  Created → Started` и точку, где она обрывается (например, `BackOff`, `Unhealthy`).
- В `describe pod` секция `Conditions` объясняет фазу: `PodScheduled`, `Initialized`,
  `ContainersReady`, `Ready` — вы можете сказать, какое из условий `False` и почему.
- Вы помните, что events живут ~1 час (`--event-ttl`), поэтому для инцидентов их надо
  снимать сразу.
