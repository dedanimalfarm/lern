# Решение сценария 02

**Причина.** в `command` контейнера подставлен `exit 1` — приложение завершается с ошибкой, kubelet перезапускает его (CrashLoopBackOff), rollout не завершается.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/deploy.yaml
```

**Проверка.**
```bash
kubectl -n lab rollout status deploy/workload-demo --timeout=120s
```
