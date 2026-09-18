# Сценарий 02: После релиза логи payment-api пропали и из Loki, и из `kubectl logs`

## Симптом

Promtail и Loki здоровы (сценарий 01 не про них), другие приложения логируются, а `payment-api`
после выката «молчит»:

```bash
kubectl -n lab logs deploy/payment-api --tail=5
#                                            <- пусто
kubectl -n lab exec deploy/payment-api -- ls -la /var/log/
# -rw-r--r-- 1 root root 48213 ... app.log   <- а файл растёт
```

## Запуск

```bash
kubectl -n lab apply -f manifests/
kubectl -n lab apply -f broken/scenario-02/payment-api.yaml
sleep 20; kubectl -n lab logs deploy/payment-api --tail=3
```

## Задание

1. Проверьте, пишет ли приложение логи вообще и куда.
2. Объясните, почему Promtail (и `kubectl logs`) их не видит.
3. Верните логи в конвейер без изменения Promtail.

Начните:

```bash
kubectl -n lab get deploy payment-api -o jsonpath='{.spec.template.spec.containers[0].args[0]}' | tail -3
kubectl -n lab exec deploy/payment-api -- tail -2 /var/log/app.log
```

<details>
<summary><strong>Подсказка 1</strong></summary>

`kubectl logs` читает только stdout/stderr контейнера — файл на диске контейнера для него не существует.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

В `args` появилось `> /var/log/app.log 2>&1`: приложение перенаправило вывод в файл. Promtail на стенде читает `/var/log/pods/…` — то, что CRI сохранил со stdout.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Контракт логирования в Kubernetes: приложение пишет в stdout/stderr, CRI кладёт это в
  `/var/log/pods/<ns>_<pod>_<uid>/<container>/N.log`, оттуда читают и `kubectl logs`, и Promtail.
- Запись в файл внутри контейнера выпадает из контракта: логов нет нигде, кроме эфемерной ФС
  пода (и пропадут с ним). Симптом выглядит как «сломался Loki», причина — в приложении.
- Если приложение умеет писать только в файл — нужен sidecar с `tail -F` в stdout
  (или Promtail-sidecar), а не правка сборщика.

</details>

<details>
<summary><strong>Решение</strong></summary>

Вернуть вывод в stdout — `solutions/scenario-02/payment-api.yaml`:

```bash
kubectl -n lab apply -f solutions/scenario-02/payment-api.yaml
sleep 15; kubectl -n lab logs deploy/payment-api --tail=3       # JSON-строки снова идут
```

</details>
