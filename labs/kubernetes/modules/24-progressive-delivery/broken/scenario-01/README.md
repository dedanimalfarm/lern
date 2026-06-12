# Сценарий 01: Релиз зарублен, хотя приложение здорово (AnalysisRun Error)

## Симптом

Любая выкатка `demo-rollout` автоматически абортится через ~1.5 минуты.
Канарейка при этом полностью здорова: поды Ready, ошибок в логах приложения
нет. Rollout уходит в `Degraded`, стабильная версия остаётся работать.

## Запуск

```bash
kubectl apply -f analysis-broken.yaml
kubectl argo rollouts set image demo-rollout app=argoproj/rollouts-demo:orange -n lab
kubectl argo rollouts get rollout demo-rollout -n lab --watch
```

## Задание

1. Определите, ЧТО зарубило релиз: приложение, метрика или сам механизм анализа.
2. Найдите точную причину в объекте AnalysisRun.
3. Почините и убедитесь, что выкатка проходит.

Начните:

```bash
kubectl argo rollouts get rollout demo-rollout -n lab
kubectl -n lab get analysisrun
```

<details>
<summary><strong>Подсказка 1</strong></summary>

В статусе Rollout — `Degraded`, message: `RolloutAborted: ... Background
analysis phase error`. Слово **error** (а не failed) — ключевое: анализ не
«измерил плохое значение», а НЕ СМОГ измерить вообще.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

Смотрите сам AnalysisRun — у каждого измерения есть message:

```bash
kubectl -n lab get analysisrun --sort-by=.metadata.creationTimestamp -o yaml | tail -40
```

Вы увидите (снято с этого кластера):

```
Post "http://prometheus.monitoring.svc:9090/api/v1/query": dial tcp:
  lookup prometheus.monitoring.svc on 169.254.25.10:53: no such host
```

(169.254.25.10 — это nodelocaldns нашего Kubespray-стенда, см. модуль 04.)
А в статусе Rollout итог: `assessed Error due to consecutiveErrors (5) >
consecutiveErrorLimit (4)`.

DNS-имя сервиса Prometheus не существует. Сравните адрес в AnalysisTemplate
с реальным сервисом: `kubectl -n monitoring get svc | grep prometheus`.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Провал ИЗМЕРЕНИЯ (Failed) и ошибка СБОРА (Error) — разные исходы с разными
  лимитами: `failureLimit` и `consecutiveErrorLimit` (по умолчанию 4).
- И то и другое в итоге абортит релиз — это безопасное поведение по умолчанию:
  «не можем доказать, что релиз хорош — не катим».
- Цена вопроса: при сломанной обвязке анализа ВСЕ релизы встают, хотя код
  здоров. Поэтому адреса/доступность Prometheus для Rollouts мониторят так же,
  как само приложение.

</details>

<details>
<summary><strong>Решение</strong></summary>

Вернуть правильный адрес (сервис kps в ns monitoring):

```bash
kubectl apply -f ../../solutions/01-analysis-address/analysis.yaml
kubectl argo rollouts retry rollout demo-rollout -n lab
kubectl argo rollouts get rollout demo-rollout -n lab --watch
# дойдёт до ручной паузы (50%) -> promote -> Healthy
```

</details>
