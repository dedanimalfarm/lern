# Решение сценария 02

**Причина.** `activeDeadlineSeconds: 5` меньше длительности работы (60 с) → Job убит по таймеру с `DeadlineExceeded`, ретраи не создаются.

**Исправление.**
```bash
kubectl -n lab delete job job-report
kubectl -n lab apply -f solutions/scenario-02/job-deadline.yaml
```

**Проверка.**
```bash
kubectl -n lab wait --for=condition=complete job/job-report --timeout=120s
```
