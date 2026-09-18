# Сценарий 02: ExternalSecret создан, а Secret так и не появился

## Симптом

```bash
kubectl -n lab get externalsecret db-from-eso-v2
# NAME             STORE        REFRESH INTERVAL   STATUS             READY
# db-from-eso-v2   fake-store   15s                SecretSyncedError  False
kubectl -n lab get secret db-from-eso-v2
# Error from server (NotFound): secrets "db-from-eso-v2" not found
```

## Запуск

```bash
kubectl -n lab apply -f manifests/eso/eso-fake.yaml
kubectl -n lab apply -f broken/scenario-02/eso-typo.yaml
sleep 20; kubectl -n lab get externalsecret db-from-eso-v2
```

## Задание

1. Найдите текст ошибки синхронизации — где ESO его хранит?
2. Сверьте ключи `remoteRef.key` с тем, что есть в источнике (`SecretStore fake-store`).
3. Исправьте и дождитесь `SecretSynced`.

Начните:

```bash
kubectl -n lab describe externalsecret db-from-eso-v2 | grep -A5 '^Status'
kubectl -n lab get secretstore fake-store -o jsonpath='{.spec.provider.fake.data[*].key}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

Условие `Ready=False`, reason `SecretSyncedError`, в message — какой именно ключ не найден в провайдере.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

В `fake-store` есть `/db/username` и `/db/password`; ExternalSecret просит `/db/passwd`. Один ненайденный ключ валит **весь** объект — Secret не создаётся частично.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- `remoteRef.key: /db/passwd` — такого ключа во внешнем источнике нет. ESO не создаёт Secret
  «наполовину»: одна ошибка = `SecretSyncedError` и отсутствие целевого Secret.
- Приложение при этом падает на старте с «secret not found» — по симптому похоже на
  забытый Secret, но причина в контракте с внешним менеджером.
- Диагностика всегда одна: `describe externalsecret` → `Status.Conditions.Message`.

</details>

<details>
<summary><strong>Решение</strong></summary>

Исправить ключ — `solutions/scenario-02/eso-typo.yaml` (`/db/password`):

```bash
kubectl -n lab apply -f solutions/scenario-02/eso-typo.yaml
sleep 20; kubectl -n lab get externalsecret,secret db-from-eso-v2
kubectl -n lab delete externalsecret db-from-eso-v2     # уборка
```

</details>
