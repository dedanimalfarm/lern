# Сценарий 01: default-deny без allow-dns сломал весь namespace

## Симптом

После включения `default-deny` приложения перестали работать: запросы по
ИМЕНАМ сервисов виснут/падают с `bad address`, хотя сами поды Running.

## Запуск

```bash
kubectl -n lab apply -f ../../manifests/app.yaml
kubectl -n lab rollout status deploy/web --timeout=120s
# применяем ТОЛЬКО default-deny (без allow-dns):
kubectl -n lab apply -f ../../manifests/netpol/00-default-deny.yaml
```

## Задание

1. Объясните, почему перестали резолвиться имена.
2. Найдите, какого egress-правила не хватает.
3. Добавьте его и проверьте, что DNS снова работает.

Начните:

```bash
kubectl -n lab run t --image=busybox:1.36 --restart=Never -i --rm -- \
  sh -c 'nslookup api 2>&1 | head; wget -qO- --timeout=4 http://api 2>&1 | head -1'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

`default-deny` закрывает И egress тоже. CoreDNS — это под в namespace
`kube-system` на порту 53. Что произойдёт с DNS-запросами подов?

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- `default-deny` запретил весь egress, включая трафик к CoreDNS (`:53`).
- Любой резолв имени (`api`, `db`, внешние домены) падает → `bad address`.
- Поды живы, но «слепы»: не могут найти адреса по именам.

</details>

<details>
<summary><strong>Решение</strong></summary>

Разрешить egress к CoreDNS первым же правилом после default-deny.

```bash
kubectl -n lab apply -f ../../manifests/netpol/01-allow-dns.yaml
kubectl -n lab run t --image=busybox:1.36 --restart=Never -i --rm -- nslookup api
# теперь имя резолвится
```

**Правило:** после `default-deny` ВСЕГДА первым добавляют `allow-dns`.

</details>
