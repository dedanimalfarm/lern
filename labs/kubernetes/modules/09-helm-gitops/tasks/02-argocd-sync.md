# 02 — Argo CD: Application, sync и self-heal

## Задача
Отдать тот же чарт под управление Argo CD, дождаться `Synced/Healthy`, затем сломать
ресурс руками и увидеть, как self-heal возвращает его к состоянию из git.

## Проверка
```bash
kubectl apply -f gitops/argocd/project.yaml -f gitops/argocd/app.yaml
kubectl -n argocd get application demo-app -w
kubectl -n argocd get application demo-app -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
kubectl -n lab get deploy demo-app -o jsonpath='{.spec.replicas}'; echo
kubectl -n lab scale deploy demo-app --replicas=3
sleep 20
kubectl -n lab get deploy demo-app -o jsonpath='{.spec.replicas}'; echo
kubectl -n argocd get application demo-app -o jsonpath='{.status.operationState.phase}{" "}{.status.operationState.message}{"\n"}'
kubectl -n argocd delete application demo-app
```

## Ожидаемый результат
- Через 1–2 минуты Application `Synced` / `Healthy`; в `lab` появился Deployment `demo-app`
  (releaseName из `spec.source.helm.releaseName`).
- Ручной `scale --replicas=3` живёт секунды: `selfHeal: true` возвращает `1`, в
  `operationState` — новый успешный sync с причиной drift.
- Вы объяснили, где хранится «правда» (git, `targetRevision: main`), почему push должен
  быть **до** синка, и что делает `prune: true`, если удалить шаблон из чарта.
- После `delete application` ресурсы в `lab` тоже удалены (finalizer `resources-finalizer`).
