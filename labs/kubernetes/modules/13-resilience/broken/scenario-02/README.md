# Сценарий 02: Drain зависает навсегда — PDB не даёт ни одного выселения

## Симптом

Приложение 3/3 здорово, а обслуживание ноды не двигается:

```bash
kubectl -n lab get pdb resilient-app-pdb
# NAME                MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
# resilient-app-pdb   100%            N/A               0                     1m   <- 0 при 3/3
kubectl create --raw /api/v1/namespaces/lab/pods/$(kubectl -n lab get pod -l app=resilient-app -o jsonpath='{.items[0].metadata.name}')/eviction -f - <<'EOF'
{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"x","namespace":"lab"}}
EOF
# Error from server: Cannot evict pod as it would violate the pod's disruption budget.
```

## Запуск

```bash
kubectl -n lab apply -f manifests/
kubectl -n lab apply -f broken/scenario-02/pdb.yaml
kubectl -n lab get pdb resilient-app-pdb
```

## Задание

1. Объясните, почему `ALLOWED DISRUPTIONS` равен 0, хотя все реплики Ready.
2. Посчитайте, какое значение `minAvailable`/`maxUnavailable` даёт drain шанс при 3 репликах.
3. Исправьте PDB и повторите выселение — оно должно пройти.

Начните:

```bash
kubectl -n lab get pdb resilient-app-pdb -o jsonpath='{.spec}{"\n"}{.status}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

`minAvailable: 100%` при 3 репликах = «все 3 должны быть живы» → выселять нельзя никого. Drain будет вечно повторять попытку.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Бюджет должен оставлять запас: `minAvailable: 2` или `maxUnavailable: 1` — тогда одна реплика может уйти на обслуживание.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- PDB с `minAvailable: 100%` формально валиден, но делает любое добровольное выселение
  невозможным: `disruptionsAllowed = 0`.
- `kubectl drain` уважает PDB и не удаляет поды силой — он ждёт и повторяет, пока
  бюджет не появится. Ноду в таком состоянии нельзя обслужить без ручного вмешательства.
- Симптом с PDB из сценария 01 отличается причиной: там бюджет 0 из-за нехватки Ready-реплик,
  здесь — из-за самого бюджета.

</details>

<details>
<summary><strong>Решение</strong></summary>

Дать бюджету запас — `solutions/scenario-02/pdb.yaml` (`minAvailable: 2`):

```bash
kubectl -n lab apply -f solutions/scenario-02/pdb.yaml
kubectl -n lab get pdb resilient-app-pdb        # ALLOWED DISRUPTIONS 1
```

</details>
