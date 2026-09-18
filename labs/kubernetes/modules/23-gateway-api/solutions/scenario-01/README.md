# Решение сценария 01

Причина: `spec.gatewayClassName: unknown-class` — такого GatewayClass нет, ни один
контроллер не берёт шлюз в работу, `PROGRAMMED` остаётся `Unknown`/`False`.

Исправление (`gateway.yaml`): `gatewayClassName: eg`. Разбор — в `broken/scenario-01/README.md`.
