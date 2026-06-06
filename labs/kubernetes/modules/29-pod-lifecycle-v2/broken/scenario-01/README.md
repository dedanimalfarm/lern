# Сценарий 01: Job не завершается — «sidecar» обычным контейнером

## Симптом
```bash
kubectl -n lab apply -f broken/scenario-01/job-broken.yaml
sleep 10
kubectl -n lab get job sidecar-job
# NAME          STATUS    COMPLETIONS   DURATION
# sidecar-job   Running   0/1           ...        <- не Complete, хотя app давно вышел
kubectl -n lab get pods -l job-name=sidecar-job
# sidecar-job-xxxxx   1/2   NotReady   ...          <- app завершён, logshipper крутится
```

## Подсказки
1. Сколько контейнеров в поде и какой из них «не хочет» заканчиваться?
2. Job считается выполненным, когда завершаются ВСЕ его контейнеры в `containers[]`.
   Логгер в бесконечном цикле — кто его остановит?
3. Что такое native sidecar и почему он решает ровно эту проблему?

## Диагностика
```bash
kubectl -n lab get pod -l job-name=sidecar-job \
  -o jsonpath='{range .status.containerStatuses[*]}{.name}={.state}{"\n"}{end}'
# app=...terminated(Completed)        <- app давно вышел
# logshipper=...running               <- а этот живёт вечно -> Job не завершается
```

## Решение
Сделать логгер **native sidecar** — перенести в `initContainers` с
`restartPolicy: Always`. Тогда под завершается, когда выходит app-контейнер, а
sidecar гасится автоматически (после app, в обратном порядке).
```bash
kubectl -n lab delete job sidecar-job
kubectl -n lab apply -f solutions/01-sidecar/job-fixed.yaml
kubectl -n lab wait --for=condition=complete job/sidecar-job --timeout=60s
kubectl -n lab get job sidecar-job          # Complete 1/1
```

## Профилактика
- Любой долгоживущий вспомогательный контейнер (лог-шиппер, прокси, агент) в Job/
  коротком воркладе — делать native sidecar (`initContainers` + `restartPolicy:
  Always`), а не класть в `containers[]`.
- Это же правило спасает от «под Job вечно 1/2 NotReady» в CI-задачах с istio-proxy.
