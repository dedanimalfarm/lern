# Лабораторная работа 24: Progressive Delivery (Argo Rollouts)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Развёртывание Argo Rollouts](#-1--argo-rollouts)
- [Часть 2: Canary с ручным подтверждением (Pause)](#-2-canary----pause)
- [Часть 3: Canary с автоматическим анализом (AnalysisTemplate)](#-3-canary----analysistemplate)
- [Часть 4: Blue/Green Deployment](#-4-bluegreen-deployment)
- [Практические задания (управление релизами)](#--)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->

> ⏱ время ~35 мин · сложность 4/5 · пререквизиты: Трек 1 и Трек 3

В этом модуле мы разберём продвинутые стратегии развёртывания — Canary (Канареечный релиз) и Blue/Green с использованием контроллера Argo Rollouts. Эти паттерны позволяют минимизировать downtime и риск выкатки сломанного кода в production, опираясь на метрики.

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
```

## Стартовая проверка

```bash
kubectl get nodes
```

## Часть 1: Развёртывание Argo Rollouts

Argo Rollouts — это Kubernetes-контроллер и набор CRD (`Rollout`, `AnalysisTemplate`), которые расширяют базовые возможности Deployment.

Установим контроллер и CLI плагин (выполняется скриптом `prepare.sh`):
```bash
verify/prepare.sh
```

Убедитесь, что плагин работает:
```bash
kubectl argo rollouts version
```

## Часть 2: Canary с ручным подтверждением (Pause)

Примените манифесты:
```bash
kubectl apply -f manifests/rollout.yaml
kubectl apply -f manifests/service.yaml
```

Мы задеплоили ресурс `Rollout`. Стратегия `canary` позволяет нам описать шаги (steps).
Текущая конфигурация в `rollout.yaml` выглядит так:
```yaml
  strategy:
    canary:
      steps:
      - setWeight: 25
      - pause:
          duration: 5s
      - setWeight: 50
      - pause: {}  # Ручная пауза до команды promote!
      - setWeight: 100
```

### Запуск обновления
Измените образ приложения, чтобы запустить rollout:
```bash
kubectl argo rollouts set image demo-rollout app=argoproj/rollouts-demo:yellow -n lab
```

### Наблюдение и продвижение (Promote)
Сразу запустите watch:
```bash
kubectl argo rollouts get rollout demo-rollout -n lab --watch
```
Вы увидите, что релиз остановился на `setWeight: 50` (состояние `Paused`).
Чтобы продолжить релиз вручную (promote):
```bash
kubectl argo rollouts promote demo-rollout -n lab
```

Если что-то пошло не так, релиз можно отменить (abort):
```bash
# kubectl argo rollouts abort demo-rollout -n lab
```

## Часть 3: Canary с автоматическим анализом (AnalysisTemplate)

Ручное подтверждение — это хорошо, но автоматика лучше. `AnalysisTemplate` позволяет Argo Rollouts делать запросы (например, в Prometheus), чтобы проверить успешность релиза.

Применим шаблон анализа:
```bash
kubectl apply -f manifests/analysis.yaml
```

В шаблоне `success-rate` описано:
```yaml
    successCondition: result == 'pass'
```
*(В реальной жизни здесь был бы PromQL запрос на вычисление процента HTTP 5xx ошибок, но для лабы мы используем мок-проверку)*

Обновите конфигурацию Rollout, раскомментировав блок `analysis` в манифесте (или применив готовый), и запустите новый релиз:
```bash
kubectl argo rollouts set image demo-rollout app=argoproj/rollouts-demo:green -n lab
```

Во время выполнения шага `setWeight: 25` Rollout создаст объект `AnalysisRun`. Посмотреть его статус:
```bash
kubectl -n lab get analysisrun
```

## Часть 4: Blue/Green Deployment

Помимо Canary, Argo Rollouts поддерживает Blue/Green — когда новая (Green) версия разворачивается полностью рядом со старой (Blue), тестируется на отдельном сервисе, и только затем основной (Active) сервис переключается на неё.

Применим манифест с Blue/Green стратегией:
```bash
kubectl apply -f manifests/rollout-bg.yaml
kubectl apply -f manifests/service-active.yaml
kubectl apply -f manifests/service-preview.yaml
```

Запустите обновление:
```bash
kubectl argo rollouts set image demo-rollout-bg app=argoproj/rollouts-demo:purple -n lab
```

Посмотрите статус:
```bash
kubectl argo rollouts get rollout demo-rollout-bg -n lab
```
Здесь вы увидите, что Preview-сервис указывает на новую версию, а Active всё ещё на старую.
Сделайте promote:
```bash
kubectl argo rollouts promote demo-rollout-bg -n lab
```

## Практические задания (управление релизами)

1. **Abort Rollout**: Запустите обновление `demo-rollout` на образ `argoproj/rollouts-demo:red`. Пока он находится на ручной паузе (50%), выполните команду `kubectl argo rollouts abort demo-rollout -n lab`. Посмотрите, что произойдёт с подами.
2. **Retry Rollout**: После abort, вы можете изменить образ на правильный или сделать `kubectl argo rollouts retry demo-rollout -n lab`. Попробуйте оба варианта.

## Чему вы научились

В этом модуле вы научились:
- Использовать контроллер Argo Rollouts для деплоя приложений.
- Настраивать стратегии Progressive Delivery: Canary и Blue/Green.
- Использовать ручные паузы (`pause: {}`) и команды `promote`/`abort`.
- Автоматизировать проверки релиза через `AnalysisTemplate`.

## Уборка

Очистите ресурсы после завершения:
```bash
../../scripts/clean/clean-module.sh modules/24-progressive-delivery
```
