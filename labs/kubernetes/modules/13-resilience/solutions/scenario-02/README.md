# Решение сценария 02

**Причина.** `minAvailable: "100%"` при трёх репликах запрещает любое выселение — `disruptionsAllowed=0`, drain зависает.

**Исправление.**
```bash
kubectl -n lab apply -f solutions/scenario-02/pdb.yaml
```

**Проверка.**
```bash
kubectl -n lab get pdb resilient-app-pdb   # ALLOWED DISRUPTIONS 1
```
