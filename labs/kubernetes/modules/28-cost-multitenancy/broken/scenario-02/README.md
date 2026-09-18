# Сценарий 02: HNC отказывается строить иерархию — «cycle»

## Симптом

```bash
bash broken/scenario-02/setup.sh
# Error from server (Forbidden): admission webhook "hierarchyconfigurations.hnc.x-k8s.io" denied the request:
#   cycle: setting the parent of "team-x" to "team-x-dev" would create a cycle
```

## Запуск

```bash
bash broken/scenario-02/setup.sh
kubectl -n team-x-dev get hierarchyconfiguration hierarchy -o jsonpath='{.spec.parent}{"\n"}'
```

## Задание

1. Нарисуйте, какое дерево получилось бы после второй команды.
2. Объясните, почему HNC отвергает это на admission, а не «как-нибудь применяет».
3. Постройте корректную иерархию: `team-x` — родитель, `team-x-dev` и `team-x-prod` — дети.

Начните:

```bash
kubectl hns tree team-x 2>/dev/null || kubectl get hierarchyconfiguration -A -o custom-columns=NS:.metadata.namespace,PARENT:.spec.parent
```

<details>
<summary><strong>Подсказка 1</strong></summary>

`team-x-dev` уже объявил родителем `team-x`. Сделать `team-x` ребёнком `team-x-dev` — замкнуть кольцо: у кого тогда наследовать RBAC и квоты?

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Иерархия HNC — дерево: политики текут только вниз. Валидирующий вебхук проверяет граф на циклы до записи объекта.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- HNC распространяет RoleBinding/NetworkPolicy/квоты от родителя к потомкам; цикл сделал бы
  распространение бесконечным, поэтому вебхук `hierarchyconfigurations.hnc.x-k8s.io`
  отклоняет запрос с `cycle`.
- Это «хорошая» ошибка: она приходит сразу и с объяснением, в отличие от сценария 01, где
  квота молча не пускала под тенанта.
- Правильная модель: один корень команды, дети — окружения; для новых детей удобнее
  `SubnamespaceAnchor` в родителе, чем ручной `HierarchyConfiguration`.

</details>

<details>
<summary><strong>Решение</strong></summary>

Ничего чинить не нужно — вебхук уже защитил кластер. Построить правильное дерево и убрать за собой:

```bash
kubectl apply -f - <<'YAML'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: SubnamespaceAnchor
metadata: { name: team-x-prod, namespace: team-x }
YAML
kubectl get hierarchyconfiguration -A -o custom-columns=NS:.metadata.namespace,PARENT:.spec.parent
bash solutions/scenario-02/reset.sh
```

</details>
