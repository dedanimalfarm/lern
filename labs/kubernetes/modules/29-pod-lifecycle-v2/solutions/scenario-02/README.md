# Решение сценария 02

**Причина.** в шаблоне Deployment `schedulingGates`, а контроллера, снимающего gate, нет — все поды `SchedulingGated`, планировщик их не рассматривает.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/deploy-gated.yaml
```

**Проверка.**
```bash
kubectl -n lab get pods -l app=gated-web   # Running
```
