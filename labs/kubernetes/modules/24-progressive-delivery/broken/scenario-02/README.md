# Сценарий 02: Rollout не стартует — `InvalidSpec`

## Симптом

Выкатка не начинается вовсе — ни канарейки, ни анализа, ни отката (это не сценарий 01):

```bash
kubectl -n lab get rollout demo-rollout
# NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE
# demo-rollout   4         4         4            4
kubectl argo rollouts -n lab get rollout demo-rollout | head -3
# Name:            demo-rollout
# Status:          ✖ Degraded
# Message:         InvalidSpec: The Rollout "demo-rollout" is invalid: spec.strategy.canary.canaryService: Invalid value: "demo-rollout-canary": service "demo-rollout-canary" not found
```

## Запуск

```bash
kubectl -n lab apply -k manifests/
kubectl -n lab apply -f broken/scenario-02/rollout.yaml
sleep 5; kubectl argo rollouts -n lab get rollout demo-rollout | head -4
```

## Задание

1. Прочитайте `Message` в статусе Rollout — это валидация, а не анализ.
2. Объясните, зачем канарейке `canaryService`/`stableService` и когда без них можно обойтись.
3. Исправьте спеку одним из двух способов и объясните разницу.

Начните:

```bash
kubectl -n lab get rollout demo-rollout -o jsonpath='{.status.conditions[?(@.type=="InvalidSpec")].message}{"\n"}'
kubectl -n lab get svc -l app=demo-rollout
```

<details>
<summary><strong>Подсказка 1</strong></summary>

Контроллер Rollouts валидирует ссылки на Service до начала выкатки: несуществующий `canaryService` = `InvalidSpec`, статус `Degraded`, поды старой ревизии продолжают работать.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

В модуле канарейка работает по долям реплик (без traffic routing) — отдельные Service ей не нужны. Либо убрать поля, либо создать оба Service с селекторами на `app: demo-rollout`.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- `canaryService`/`stableService` нужны, когда доли трафика задаёт Ingress/mesh (traffic
  routing): контроллер переключает селекторы этих Service по `rollouts-pod-template-hash`.
  Без них веса реализуются числом реплик — как в базовом сценарии модуля.
- Ссылка на несуществующий Service → `InvalidSpec` на входе; выкатка не запускается,
  старая ревизия продолжает обслуживать трафик — «безопасный» отказ.
- Отличие от сценария 01: там выкатка стартовала и была отменена анализом; здесь
  контроллер отвергает спеку до первого шага.

</details>

<details>
<summary><strong>Решение</strong></summary>

Убрать ссылки на Service (в модуле traffic routing не используется) — `solutions/scenario-02/rollout.yaml`:

```bash
kubectl -n lab apply -f solutions/scenario-02/rollout.yaml
kubectl argo rollouts -n lab get rollout demo-rollout | head -3     # Healthy
```
Альтернатива — создать `demo-rollout-canary` и `demo-rollout-stable` (селектор `app: demo-rollout`) и оставить поля.

</details>
