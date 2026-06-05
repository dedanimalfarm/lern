# Сценарий 01: Job не завершается — `BackoffLimitExceeded`

## Симптом

```bash
kubectl -n lab apply -f broken/scenario-01/job-broken.yaml
kubectl -n lab get job job-flaky
# NAME        STATUS   COMPLETIONS   DURATION   AGE
# job-flaky   Failed   0/1           ...        40s
kubectl -n lab get pods -l job-name=job-flaky
# job-flaky-xxxxx   0/1   Error   ...      <- три упавших пода, новых нет
```

## Подсказки

1. Job ретраит САМ — почему он перестал создавать поды? Сколько их всего?
2. Посмотри причину завершения Job: `kubectl -n lab describe job job-flaky`
   (ищи `reason=BackoffLimitExceeded`) и логи упавшего пода
   (`kubectl -n lab logs -l job-name=job-flaky --previous` или без `--previous`).
3. `backoffLimit=2` => всего 1+2=3 попытки. После них Job сдаётся НАВСЕГДА —
   правкой манифеста живой Job уже не «оживить», его нужно удалить и пересоздать
   (поле template иммутабельно у запущенного Job).

## Диагностика

```bash
kubectl -n lab describe job job-flaky | grep -A2 -iE "reason|warning"
# Warning  BackoffLimitExceeded  Job has reached the specified backoff limit
kubectl -n lab logs -l job-name=job-flaky --tail=2
# cat: can't open '/data/input.txt': No such file or directory   <- корень причины
```

## Решение

Причина — команда читает несуществующий файл. Чиним команду (или монтируем
данные) и ПЕРЕСОЗДаём Job (старый Failed-Job удаляем):

```bash
kubectl -n lab delete job job-flaky
kubectl -n lab apply -f solutions/01-backoff/job-fixed.yaml
kubectl -n lab wait --for=condition=complete job/job-flaky --timeout=60s
kubectl -n lab get job job-flaky
# job-flaky   Complete   1/1   ...
```

## Профилактика

- `backoffLimit` подбирают осознанно: слишком большой = долго «бьётся» в стену и
  жжёт ресурсы; 0 = ни одного ретрая (для идемпотентных задач, где ретрай вреден).
- Для отсева НЕ-ретраябельных ошибок (баг кода vs временный сбой сети) используют
  `podFailurePolicy` (Часть 3): `FailJob` на «фатальных» exit-кодах — не тратить
  все ретраи на заведомо безнадёжную задачу.
