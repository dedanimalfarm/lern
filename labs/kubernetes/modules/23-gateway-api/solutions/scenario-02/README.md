# Решение сценария 02

Причина: `spec.parentRefs[0].name: typo-gateway` — такого Gateway нет, маршрут не принят
(`Accepted=False`, `InvalidParentRef`/`NoMatchingParent`).

Исправление (`httproute.yaml`): `parentRefs[0].name: demo-gateway`. Разбор — в
`broken/scenario-02/README.md`.
