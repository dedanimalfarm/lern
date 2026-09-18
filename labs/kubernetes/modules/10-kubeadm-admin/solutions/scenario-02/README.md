# Решение сценария 02

**Причина.** после drain ноды остались `SchedulingDisabled` (cordon не снят) — новые поды не планируются, старые работают, ресурсы свободны.

**Исправление.**
```bash
bash solutions/scenario-02/fix.sh
```

**Проверка.**
```bash
kubectl get nodes
kubectl -n lab get pods -l app=drain-demo
```
