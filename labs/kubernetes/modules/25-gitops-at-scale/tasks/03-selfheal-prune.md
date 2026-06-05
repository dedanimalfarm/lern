# 03 — selfHeal и prune на масштабе

## Задача
Убедиться, что GitOps возвращает кластер к состоянию git: ручной drift
откатывается (`selfHeal`), а удалённое из git удаляется из кластера (`prune`).

## Проверка — selfHeal (drift в кластере откатывается)
```bash
# Руками «подкрутить» прод вопреки git:
kubectl -n lab-prod scale deploy web --replicas=7
sleep 20
kubectl -n lab-prod get deploy web      # снова 3/3 — Argo вернул к git (overlay prod=3)
```

## Проверка — prune (удаление из git => удаление из кластера)
```bash
# Симуляция: временно «убрать» staging из набора (env: dev/prod в локальной копии),
# применить — Application web-staging удалится, а с prune=true уедет и его deploy.
# (В реальном GitOps это делается КОММИТОМ в git, не kubectl edit.)
kubectl -n argocd get applications      # web-staging исчез
kubectl get ns lab-staging              # namespace опустел (deploy удалён)
```

## Ожидаемый результат
selfHeal: ручной replicas=7 откатывается к 3. prune: убранное из набора окружение
вычищается из кластера (Application + его ресурсы).
