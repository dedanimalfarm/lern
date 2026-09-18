# Решение сценария 02

**Причина.** frontend экспортирует OTLP по gRPC на HTTP-порт коллектора 4318 → `StatusCode.UNAVAILABLE`, спаны frontend теряются.

**Исправление.**
```bash
bash solutions/scenario-02/fix.sh
```

**Проверка.**
```bash
kubectl -n lab logs deploy/frontend --tail=20 | grep -ic export   # 0
```
