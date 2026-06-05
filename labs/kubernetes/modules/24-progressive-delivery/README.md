# Лабораторная работа 24: Progressive Delivery (Argo Rollouts)
> ⏱ время ~25 мин · сложность 4/5 · пререквизиты: Трек 1 и Трек 3

В этом модуле мы разберём продвинутые стратегии развёртывания — Canary (Канареечный релиз) и Blue/Green с использованием контроллера Argo Rollouts. Эти паттерны позволяют минимизировать downtime и риск выкатки сломанного кода в production.

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
```

## Стартовая проверка

```bash
kubectl get nodes
```

## 1. Развёртывание Argo Rollouts

Argo Rollouts — это Kubernetes-контроллер и набор CRD (`Rollout`, `AnalysisTemplate`), которые расширяют базовые возможности Deployment.

Установим контроллер и CLI плагин (выполняется скриптом `prepare.sh`):
```bash
verify/prepare.sh
```

## 2. Изучение Canary релиза

Примените манифесты из папки `manifests`:
```bash
kubectl apply -k manifests/
```

Мы задеплоили ресурс `Rollout` с именем `demo-rollout`. Обратите внимание на секцию `strategy` в манифесте `rollout.yaml`:
```yaml
  strategy:
    canary:
      steps:
      - setWeight: 25
      - pause:
          duration: 5s
      - setWeight: 50
      - pause:
          duration: 5s
      - setWeight: 100
```
В реальном сценарии вместо `duration: 5s` мы могли бы использовать бессрочную паузу `- pause: {}` (ожидающую ручного подтверждения) или автоматический `AnalysisRun` с запросами в Prometheus, чтобы проверять, нет ли 500-х ошибок. Для простоты лабораторной здесь используется короткая автоматическая пауза.

## Практические задания

### Задание 1. Наблюдение за релизом
С помощью плагина kubectl отследите статус развёртывания:
```bash
kubectl argo rollouts get rollout demo-rollout -n lab
```

### Задание 2. Обновление образа (Trigger a rollout)
Измените образ приложения, чтобы запустить процесс прогрессивной доставки:
```bash
kubectl argo rollouts set image demo-rollout app=argoproj/rollouts-demo:yellow -n lab
```

И сразу запустите watch:
```bash
kubectl argo rollouts get rollout demo-rollout -n lab --watch
```
Вы увидите, как Rollout направляет 25% трафика на новую версию (Canary), ждёт 5 секунд, затем 50%, и наконец 100%.

## Финальная карта ресурсов модуля

| Ресурс | Тип | Роль |
|--------|-----|------|
| `demo-rollout` | Rollout | Управляет версиями ReplicaSet и распределением трафика. |
| `demo-rollout-svc` | Service | Направляет трафик на поды, выбранные Rollout'ом. |

## Чему вы научились

В этом модуле вы научились:
- Использовать контроллер Argo Rollouts для деплоя приложений.
- Настраивать стратегии Progressive Delivery (Canary).
- Управлять весом (Weight) трафика между разными версиями приложения.

## Уборка

Очистите ресурсы после завершения:
```bash
../../scripts/clean/clean-module.sh modules/24-progressive-delivery
```
