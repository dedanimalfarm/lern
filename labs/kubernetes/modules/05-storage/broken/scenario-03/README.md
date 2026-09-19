# Сценарий 03: Данные пропадают при каждом пересоздании пода

## Симптом

Приложение пишет журнал в `/data`, ошибок нет, под `Running`. Но после любого
пересоздания пода счётчик строк начинается заново:

```bash
kubectl -n lab logs deploy/notes-app | tail -2
# запись 10:14:03 в /data/notes.log
# строк в журнале: 1
kubectl -n lab delete pod -l app=notes-app
kubectl -n lab logs deploy/notes-app | tail -1
# строк в журнале: 1        <- снова 1, прошлая запись исчезла
```

## Запуск

```bash
kubectl -n lab apply -f broken/scenario-03/deploy.yaml
kubectl -n lab rollout status deploy/notes-app --timeout=90s
kubectl -n lab logs deploy/notes-app | tail -2
```

## Задание

1. Найдите, куда на самом деле пишутся данные и чем этот том является.
2. Объясните, почему ошибок нет ни в логах, ни в событиях.
3. Переведите приложение на том, переживающий под, и докажите, что записи копятся.

Начните:

```bash
kubectl -n lab get deploy notes-app -o jsonpath='{.spec.template.spec.volumes}{"\n"}'
kubectl -n lab get pvc
```

<details>
<summary><strong>Подсказка 1</strong></summary>

Ошибок нет, потому что запись действительно происходит — вопрос в том, куда. Посмотрите тип тома в `spec.volumes`.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

`emptyDir` — каталог, который создаётся при старте пода на ноде и удаляется вместе с подом. Он полезен как кэш или обмен между контейнерами, но не как хранилище.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Том `data` объявлен как `emptyDir: {}`. Такой том живёт ровно столько, сколько живёт
  **под**: пересоздание (delete, rollout, переезд на другую ноду, вытеснение) стирает
  данные. Kubernetes не считает это ошибкой — контракт `emptyDir` именно такой.
- Симптом коварен: приложение здорово, события чистые, «потеря» видна только по
  бизнес-данным. Поэтому персистентность проверяют не логами, а тестом
  «записал → пересоздал под → прочитал».
- Нужен `PersistentVolumeClaim`: том выделяется отдельно от пода и переживает его.
  На стенде PVC обслуживает `local-path` (StorageClass по умолчанию), режим
  `WaitForFirstConsumer` — том создаётся на той ноде, куда сел под.

</details>

<details>
<summary><strong>Решение</strong></summary>

Перевести том на PVC — `solutions/scenario-03/deploy.yaml` (создаёт PVC `notes-data`):

```bash
kubectl -n lab apply -f solutions/scenario-03/deploy.yaml
kubectl -n lab rollout status deploy/notes-app --timeout=120s
kubectl -n lab get pvc notes-data                     # Bound
kubectl -n lab delete pod -l app=notes-app
kubectl -n lab rollout status deploy/notes-app --timeout=120s
kubectl -n lab logs deploy/notes-app | tail -1        # строк в журнале: 2 — данные пережили под
```

</details>
