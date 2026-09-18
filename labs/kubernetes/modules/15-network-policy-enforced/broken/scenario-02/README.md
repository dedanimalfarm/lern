# Сценарий 02: Политика на месте, а web → api не ходит

## Симптом

Все политики применены, `default-deny` и `allow-dns` работают, но фронтенд не достучится до API:

```bash
kubectl -n lab exec deploy/web -- wget -qO- -T 3 http://api
# wget: download timed out
kubectl -n lab get netpol
# NAME           POD-SELECTOR   AGE
# api-policy     app=api        1m     <- политика есть
# ...
```

## Запуск

```bash
kubectl -n lab apply -k manifests/
kubectl -n lab apply -f broken/scenario-02/api-policy.yaml
kubectl -n lab exec deploy/web -- wget -qO- -T 3 http://api
```

## Задание

1. Определите, на какой стороне отбрасывается трафик: egress у `web` или ingress у `api`.
2. Сравните селекторы политики с реальными метками подов.
3. Исправьте политику и подтвердите доступ.

Начните:

```bash
kubectl -n lab describe netpol api-policy | sed -n '/Allowing ingress/,/Allowing egress/p'
kubectl -n lab get pods --show-labels -l app=web
```

<details>
<summary><strong>Подсказка 1</strong></summary>

Политика — это селекторы. `describe netpol api-policy` показывает `From: PodSelector: app=frontend`. Есть ли у подов web такая метка?

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

У подов web метки `app=web, tier=frontend`. Селектор `app: frontend` не совпадает ни с одним подом — правило разрешает трафик «ниоткуда».

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- В `ingress.from.podSelector` политики `api-policy` опечатка: `app: frontend` вместо `app: web`
  (перепутали значение с меткой `tier=frontend`).
- Селектор не матчит ни одного пода → правило не разрешает ничего, а `default-deny` режет
  остальное. Политика «существует», но эффективно пуста — самая частая ошибка
  микросегментации.
- Проверка селекторов: `kubectl get pods -l <селектор из политики>` — если пусто, правило
  мёртвое.

</details>

<details>
<summary><strong>Решение</strong></summary>

Вернуть селектор `app: web` — `solutions/scenario-02/api-policy.yaml`:

```bash
kubectl -n lab apply -f solutions/scenario-02/api-policy.yaml
kubectl -n lab exec deploy/web -- wget -qO- -T 3 http://api | head -1
```

</details>
