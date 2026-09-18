# Решение сценария 02

**Причина.** попытка сделать `team-x` ребёнком собственного потомка `team-x-dev` — вебхук HNC отклоняет цикл на admission; кластер не пострадал.

**Исправление.**
```bash
bash solutions/scenario-02/reset.sh
```

**Проверка.**
```bash
kubectl get ns team-x team-x-dev 2>&1 | tail -1   # NotFound
```
