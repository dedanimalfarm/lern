# Сценарий 02: Custom Resource не удаляется — вечный `Terminating`

## Симптом

```bash
kubectl -n lab delete webapp stuck-webapp --timeout=10s
# error: timed out waiting for the condition on webapps/stuck-webapp
kubectl -n lab get webapp stuck-webapp -o jsonpath='{.metadata.deletionTimestamp}{"\n"}'
# 2026-09-19T10:00:00Z                       <- удаление начато, но не завершается
```

## Запуск

```bash
kubectl -n lab apply -f manifests/crd.yaml
kubectl -n lab apply -f broken/scenario-02/webapp-finalizer.yaml
kubectl -n lab delete webapp stuck-webapp --timeout=10s
```

## Задание

1. Объясните, что означает `deletionTimestamp` при живом объекте.
2. Найдите, что именно держит объект, и кто должен был это снять.
3. Снимите блокировку правильно и объясните риск такого действия в проде.

Начните:

```bash
kubectl -n lab get webapp stuck-webapp -o jsonpath='{.metadata.finalizers}{"\n"}'
kubectl -n lab get pods -A | grep -i operator || echo "оператор не запущен"
```

<details>
<summary><strong>Подсказка 1</strong></summary>

`metadata.finalizers` — список «замков»: API-сервер не удалит объект, пока все они не сняты. Снимает их контроллер, который их поставил, после своей уборки.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Финализатор `lab.example.com/cleanup-external-dns` поставлен, а контроллера, который его обрабатывает, в кластере нет — снять некому.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Finalizer — механизм гарантированной уборки внешних ресурсов (DNS-записи, диски, записи
  в облаке): контроллер ставит его при создании и снимает после cleanup. Удаление объекта =
  установка `deletionTimestamp` + ожидание пустого списка finalizers.
- Если контроллер умер или его вообще не запускали, объект висит в `Terminating` вечно —
  как и namespace с «застрявшими» CR в сценарии из Части 5.
- Ручное снятие finalizer (`patch … finalizers: null`) — аварийный выход: внешние ресурсы
  останутся неубранными. В проде сначала чинят/запускают контроллер.

</details>

<details>
<summary><strong>Решение</strong></summary>

Снять finalizer вручную — `solutions/scenario-02/fix.sh`:

```bash
bash solutions/scenario-02/fix.sh
# Error from server (NotFound): webapps.lab.example.com "stuck-webapp" not found   <- удалился
```

</details>
