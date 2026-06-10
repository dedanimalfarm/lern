# Сценарий 02: Агрессивная Liveness Probe (CrashLoopBackOff)

## Симптом

Deployment создается, но Pod постоянно перезапускается и переходит в состояние `CrashLoopBackOff`. Приложение так и не становится готовым к обработке трафика.

## Запуск

```bash
kubectl -n lab apply -f deploy.yaml
kubectl -n lab get pods -l app=slow-app -w
```

## Задание

1. Выясните причину постоянных рестартов контейнера.
2. Поймите, почему приложение не успевает инициализироваться.
3. Добавьте правильную конфигурацию (без изменения логики старта самого приложения), чтобы защитить медленный запуск.

Начните:

```bash
kubectl -n lab describe pod -l app=slow-app
kubectl -n lab get events --sort-by=.lastTimestamp | tail -15
```

<details>
<summary><strong>Подсказка 1</strong></summary>

В логах событий (`kubectl get events`) вы увидите, что контейнер убивается (Killing), потому что провалилась `Liveness probe`. 
Почему она проваливается?

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Приложение (согласно параметру `command`) специально имитирует медленный запуск, "засыпая" на 15 секунд перед запуском веб-сервера.

Посмотрим на параметры `livenessProbe` в `deploy.yaml`:
- `initialDelaySeconds: 2`
- `periodSeconds: 2`
- `failureThreshold: 3`

Сколько времени пройдет с момента старта контейнера до того, как Kubernetes посчитает его зависшим и убьет?

</details>

<details>
<summary><strong>Подсказка 3</strong></summary>

Проба начинает проверять через 2 секунды. Затем делает 3 попытки каждые 2 секунды. Через 8 секунд (2 + 3*2) Kubernetes решает, что контейнер "мертв", и перезапускает его.
Но приложению нужно 15 секунд для старта! Контейнер попадает в бесконечный цикл рестартов.

Вместо того чтобы увеличивать `initialDelaySeconds` у `livenessProbe` до огромных значений, в Kubernetes есть специальная проба для защиты медленного старта. Как она называется?

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Приложению требуется время на запуск (например, прогрев кэша, миграции БД).
- Агрессивная `livenessProbe` убивает его до завершения инициализации.
- Для таких случаев существует `startupProbe`. Пока она не завершится успешно, `livenessProbe` и `readinessProbe` не выполняются.

</details>

<details>
<summary><strong>Решение</strong></summary>

Добавьте `startupProbe` в спецификацию контейнера, настроив `failureThreshold` так, чтобы дать приложению достаточно времени (например, 15 проверок каждые 2 секунды = 30 секунд времени на старт).

```bash
kubectl -n lab apply -f ../../solutions/02-liveness-crashloop/deploy.yaml
kubectl -n lab get pods -l app=slow-app -w
```
Подождите около 20 секунд, и Pod успешно перейдет в `Running` и `1/1 Ready`.

</details>
