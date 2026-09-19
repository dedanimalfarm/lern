# Сценарий 03: После «харденинга» под не стартует

## Симптом

Манифест прошёл ревью безопасности (non-root, drop ALL, read-only rootfs), но
приложение не поднимается:

```bash
kubectl -n lab get pods -l app=hardened-web
# NAME                  READY   STATUS                       RESTARTS   AGE
# hardened-web-...      0/1     CreateContainerConfigError   0          30s
```

## Запуск

```bash
kubectl -n lab apply -f broken/scenario-03/deploy.yaml
kubectl -n lab get pods -l app=hardened-web -w
```

## Задание

1. Прочитайте причину в событиях пода — она называется прямым текстом.
2. Объясните, кто и на каком этапе останавливает контейнер: admission, kubelet или само приложение.
3. Почините так, чтобы **все** ограничения остались в силе.

Начните:

```bash
kubectl -n lab describe pod -l app=hardened-web | grep -A5 '^Events'
kubectl -n lab get deploy hardened-web -o jsonpath='{.spec.template.spec.containers[0].securityContext}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

В событиях: `Error: container has runAsNonRoot and image will run as root`. Это не admission (объект создан) и не приложение (оно не стартовало) — это kubelet перед запуском контейнера.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Официальный `nginx` запускается от root: master-процесс биндит порт 80 и пишет в `/var/cache/nginx`. С `runAsNonRoot: true` kubelet отказывается его запускать, а `readOnlyRootFilesystem: true` не даст писать кэш даже не-root образу.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- `runAsNonRoot: true` — проверка kubelet: если у образа `USER` не задан или равен root,
  а числовой UID не переопределён, контейнер не запускается
  (`CreateContainerConfigError`). Под при этом «создан», но не работает.
- Даже если задать `runAsUser: 101`, останется вторая проблема: с
  `readOnlyRootFilesystem: true` nginx не сможет писать во временные каталоги
  (`/var/cache/nginx`, `/tmp`) и упадёт уже на старте.
- Правильный путь — не ослаблять политику, а взять образ, спроектированный под
  non-root (`nginxinc/nginx-unprivileged` слушает 8080 и не требует root), и
  подмонтировать `emptyDir` туда, куда приложение обязано писать. Это ровно то, чего
  требует профиль `restricted` из модуля 14.

</details>

<details>
<summary><strong>Решение</strong></summary>

Заменить образ на unprivileged и дать emptyDir под кэш — `solutions/scenario-03/deploy.yaml`:

```bash
kubectl -n lab apply -f solutions/scenario-03/deploy.yaml
kubectl -n lab rollout status deploy/hardened-web --timeout=90s
kubectl -n lab get pods -l app=hardened-web          # 1/1 Running
kubectl -n lab exec deploy/hardened-web -- id        # uid=101(nginx), не root
```

</details>
