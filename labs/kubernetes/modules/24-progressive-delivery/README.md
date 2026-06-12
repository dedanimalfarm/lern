# Лабораторная работа 24: Progressive Delivery — Argo Rollouts: Canary, анализ по метрикам, Blue/Green

## Оглавление
<!-- TOC -->
- [Цели](#)
- [Предварительные требования](#-)
- [Часть 1: Установка Argo Rollouts](#-1--argo-rollouts)
  - [Теория для изучения перед частью](#----)
- [Часть 2: Canary с ручным подтверждением](#-2-canary---)
- [Часть 3: Автоанализ по метрикам и АВТО-откат](#-3------)
  - [Теория для изучения перед частью](#----)
  - [3.1 Успешный релиз под надзором](#31----)
  - [3.2 Сломанный релиз: автоматический откат](#32----)
- [Часть 4: Blue/Green](#-4-bluegreen)
  - [Теория для изучения перед частью](#----)
- [Часть 5: Argo Rollouts vs Flux Flagger](#-5-argo-rollouts-vs-flux-flagger)
- [Часть 6: Troubleshooting](#-6-troubleshooting)
- [Практические задания (отработка)](#--)
- [Проверка модуля](#-)
- [Шпаргалка](#)
- [Финальная карта ресурсов модуля](#---)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


⏱ время: 60–75 мин · 🎚 сложность: 4/5 · ⚙️ пререквизиты: модуль 03 (Deployments), модуль 17 (Prometheus — для Части 3)

## Цели

1. Понять, чем progressive delivery отличается от RollingUpdate и какие гарантии даёт.
2. Прокатить Canary-релиз с ручным подтверждением (pause → promote / abort).
3. Сделать релиз самопроверяющимся: настоящий анализ по метрикам Prometheus и АВТО-откат сломанной канарейки.
4. Прокатить Blue/Green с превью-окружением и мгновенным переключением.
5. Осознанно выбрать инструмент: Argo Rollouts vs Flux Flagger.

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl get nodes
# Нужен Prometheus из модуля 17 (kube-prometheus-stack в ns monitoring) —
# Часть 3 ходит в него за метриками.
kubectl -n monitoring get svc kps-kube-prometheus-stack-prometheus
```

## Часть 1: Установка Argo Rollouts

### Теория для изучения перед частью

Стандартный Deployment умеет только RollingUpdate: новые поды заменяют старые
с фиксированным темпом, без пауз, без проверок, и «откат» — это ручной
`rollout undo` ПОСЛЕ того, как пользователи уже увидели проблему.

**Argo Rollouts** — контроллер + CRD `Rollout` (drop-in замена Deployment:
тот же template, но поле `strategy` сильно богаче):

- **Canary**: новая версия получает долю трафика по шагам
  (`setWeight` → `pause` → ...), на каждом шаге можно остановиться,
  проверить и откатить.
- **Blue/Green**: новая версия поднимается ПОЛНОСТЬЮ рядом со старой,
  смотрит в отдельный preview-Service, переключение active — атомарное.
- **AnalysisTemplate/AnalysisRun**: автоматическая проверка релиза по
  метрикам (Prometheus, Datadog, job, ...) — провал = автоматический abort.

> 💡 Как Rollouts делит трафик БЕЗ service mesh: вес канарейки реализуется
> МАСШТАБИРОВАНИЕМ ReplicaSet'ов (25% = 1 под из 4 за общим Service).
> Точность ограничена числом реплик; точные веса (1%, header-routing) дают
> trafficRouting-интеграции (nginx, Istio, Gateway API API) — см. Часть 5.

```bash
verify/prepare.sh          # ставит контроллер v1.9.0 (запинован) + kubectl-плагин
kubectl argo rollouts version
```

**Контрольные вопросы:**
1. Какие два недостатка RollingUpdate решает progressive delivery?
2. Почему точность `setWeight` на нашем стенде кратна 25%?

---

## Часть 2: Canary с ручным подтверждением

Применяем манифесты (Rollout, Services, AnalysisTemplate):

```bash
kubectl apply -f manifests/
kubectl argo rollouts get rollout demo-rollout -n lab
```

Стратегия в `manifests/rollout.yaml`:

```yaml
  strategy:
    canary:
      steps:
      - setWeight: 25
      - pause: {duration: 5s}
      - setWeight: 50
      - pause: {}        # ручная пауза до promote!
      - setWeight: 100
```

Запускаем релиз и наблюдаем:

```bash
kubectl argo rollouts set image demo-rollout app=argoproj/rollouts-demo:yellow -n lab
kubectl argo rollouts get rollout demo-rollout -n lab --watch
```

Реальное состояние на ручной паузе (снято со стенда):

```
Status:          ॥ Paused
Message:         CanaryPauseStep
Strategy:        Canary
  Step:          3/5
  SetWeight:     50
  ActualWeight:  50
Images:          argoproj/rollouts-demo:blue (stable)
                 argoproj/rollouts-demo:yellow (canary)
├──⧉ demo-rollout-676df89f6b   ReplicaSet  ✔ Healthy  canary
└──⧉ demo-rollout-dc778d98d    ReplicaSet  ✔ Healthy  stable
```

Половина подов — новые, половина — старые; релиз ЖДЁТ человека:

```bash
kubectl argo rollouts promote demo-rollout -n lab    # продолжить
# kubectl argo rollouts abort demo-rollout -n lab    # или откатить
```

**Контрольные вопросы:**
1. Что произойдёт с подами при `abort` на шаге 50%?
2. Чем `pause: {duration: 5s}` отличается от `pause: {}` по смыслу процесса?

---

## Часть 3: Автоанализ по метрикам и АВТО-откат

### Теория для изучения перед частью

`AnalysisTemplate` описывает измерения; Rollout создаёт по нему `AnalysisRun`:

- **interval/count** — как часто и сколько раз измерять;
- **successCondition** — выражение над результатом запроса;
- **failureLimit** — сколько ПРОВАЛЬНЫХ измерений терпим (значение плохое);
- **consecutiveErrorLimit** — сколько ОШИБОК сбора терпим (Prometheus недоступен);
- провал любого лимита ⇒ AnalysisRun Failed/Error ⇒ **автоматический abort**
  и откат на stable. Релиз без человека отменяет сам себя.

Наш анализ — настоящий (см. `manifests/analysis.yaml`): Rollouts ходит в
Prometheus стенда и считает долю Ready-подов rollout'а:

```promql
sum(kube_pod_status_ready{namespace="lab", condition="true", pod=~"demo-rollout-.*"})
/
count(kube_pod_status_ready{namespace="lab", condition="true", pod=~"demo-rollout-.*"})
```

`successCondition: result[0] >= 0.9`. В проде вместо ready-доли сюда кладут
error-rate / latency приложения — механика та же.

### 3.1 Успешный релиз под надзором

Анализ фоновый (`startingStep: 0`) — он уже бежал в Части 2:

```bash
kubectl -n lab get analysisrun
# NAME                        STATUS       AGE
# demo-rollout-676df89f6b-2   Successful   53s
```

### 3.2 Сломанный релиз: автоматический откат

Выкатываем заведомо битый образ и НИЧЕГО не трогаем:

```bash
kubectl argo rollouts set image demo-rollout app=argoproj/rollouts-demo:does-not-exist -n lab
kubectl argo rollouts get rollout demo-rollout -n lab --watch
```

Через ~1.5 минуты (снято со стенда):

```
Status:          ✖ Degraded
Message:         RolloutAborted: Rollout aborted update to revision 6:
  Background analysis phase error/failed: Metric "pods-ready-fraction"
  assessed Failed due to failed (2) > failureLimit (1)
Images:          argoproj/rollouts-demo:yellow (stable)
  SetWeight:     0
Replicas:        Desired: 4  Ready: 4
```

Канарейка не стала Ready → доля упала ниже 0.9 → два провала измерения →
abort. **Stable-версия не пострадала, человек не участвовал.** Вернуться:

```bash
kubectl argo rollouts set image demo-rollout app=argoproj/rollouts-demo:yellow -n lab
kubectl argo rollouts retry rollout demo-rollout -n lab
```

> ⚠️ `startingStep: 0` принципиален: канарейка с битым образом не достигает
> `setWeight: 25`, и анализ «с шага 1» просто не успел бы начаться — релиз
> висел бы до progressDeadline (наступили вживую).

**Контрольные вопросы:**
1. Чем исход Failed отличается от Error и почему у них разные лимиты?
2. Почему «не можем измерить» по умолчанию означает «откатить»?
3. Что положить в successCondition для прод-сервиса вместо ready-доли?

---

## Часть 4: Blue/Green

### Теория для изучения перед частью

Blue/Green не делит трафик: новая версия (green) поднимается ЦЕЛИКОМ рядом со
старой и получает отдельный **preview**-Service. Тестируете превью сколько
угодно; `promote` атомарно переключает **active**-Service (Rollouts меняет
`rollouts-pod-template-hash` в его selector). Расплата — двойная ёмкость на
время релиза.

```bash
kubectl argo rollouts set image demo-rollout-bg app=argoproj/rollouts-demo:orange -n lab
sleep 40
kubectl argo rollouts get rollout demo-rollout-bg -n lab
```

Реальное состояние паузы (`autoPromotionEnabled: false`):

```
Status:          ॥ Paused
Message:         BlueGreenPause
Images:          argoproj/rollouts-demo:orange (preview)
                 argoproj/rollouts-demo:purple (stable, active)
Replicas:        Desired: 4   Current: 8   <- двойная ёмкость!
```

Доказательство «двух миров» curl'ом из кластера (сервисы на порту 80):

```bash
kubectl -n lab run curl-bg --image=curlimages/curl:8.11.1 --restart=Never --rm -i \
  --overrides='{"spec":{"containers":[{"name":"curl-bg","image":"curlimages/curl:8.11.1","command":["sh","-c","echo -n \"active:  \"; curl -s http://rollout-active/color; echo; echo -n \"preview: \"; curl -s http://rollout-preview/color"],"resources":{"requests":{"cpu":"10m","memory":"16Mi"},"limits":{"cpu":"50m","memory":"32Mi"}}}]}}'
# active:  "purple"
# preview: "orange"

kubectl argo rollouts promote demo-rollout-bg -n lab
# ... через ~30с:
# active after promote: "orange"
```

> 💡 Явные resources в curl-поде не каприз: ns `lab` живёт под ResourceQuota,
> а Blue/Green в момент перехода и так удваивает потребление (8 подов).
> Это же причина, почему у rollout-подов в манифестах прописаны маленькие
> requests/limits — дефолт LimitRange (300m) не влез бы в квоту.

**Контрольные вопросы:**
1. Что именно меняет promote в объекте Service?
2. Когда Blue/Green уместнее Canary, несмотря на двойную ёмкость?
3. Куда смотрят оба сервиса ПОСЛЕ promote и до следующего релиза?

---

## Часть 5: Argo Rollouts vs Flux Flagger

Оба — CNCF-инструменты progressive delivery, но устроены по-разному:

| | **Argo Rollouts** | **Flagger (Flux)** |
|---|---|---|
| Модель | СВОЙ CRD `Rollout` ВМЕСТО Deployment | надстройка НАД обычным Deployment (создаёт `-primary` копию) |
| Миграция | переписать workload на Rollout | повесить CRD `Canary` на существующий Deployment |
| Трафик без mesh | умеет (масштабированием RS, как у нас) | НЕ умеет — обязателен mesh/ingress-провайдер (Istio, Linkerd, nginx, Gateway API) |
| Точные веса/header-routing | через trafficRouting-интеграции | да, это его родная стихия |
| Анализ | AnalysisTemplate (Prometheus, Datadog, job, web, ...) | встроенные checks + webhooks (load-test перед шагом) |
| Управление | kubectl-плагин, UI-дашборд, promote/abort руками | полностью декларативно, ручного promote нет (только gate-webhooks) |
| Экосистема | Argo CD/Workflows (UI в Argo CD) | Flux, GitOps Toolkit |

Практическое правило: **уже живёте в Argo CD и хотите ручные паузы — Rollouts;
живёте во Flux + mesh и хотите полную автоматику — Flagger.** Концепции
(canary, анализ по метрикам, авто-откат) идентичны — выучив одно, читаете
конфиги второго свободно.

---

## Часть 6: Troubleshooting

| Симптом | Причина | Диагностика / фикс |
|---------|---------|--------------------|
| Любой релиз абортится, приложение здорово | анализ не может ИЗМЕРИТЬ (Error, не Failed) | `broken/scenario-01/`; смотреть message в AnalysisRun |
| Rollout висит Progressing, канарейка 0/1 | битый образ/краш канарейки ДО первого шага | `kubectl describe pod`; abort и чинить образ |
| ReplicaFailure, поды не создаются | ResourceQuota ns (наш стенд: limits.cpu=2) | `kubectl -n lab describe quota`; явные маленькие resources |
| Rollout Degraded: ProgressDeadlineExceeded | канарейка не стала доступной за deadline | после устранения причины — `retry rollout` |
| `kubectl argo rollouts` — unknown command | не установлен kubectl-плагин | `verify/prepare.sh` |
| Время паузы вышло, релиз стоит | пауза `pause: {}` без duration — ждёт promote | это by design: ручной gate |

---

## Практические задания (отработка)

1. Прогоните `abort` на ручной паузе и объясните, что произошло с двумя
   ReplicaSet'ами; верните релиз через `retry`.
2. Ужесточите анализ: `successCondition: result[0] >= 1.0`, `failureLimit: 0` —
   и прокатите здоровый релиз. Пройдёт ли он? Почему «слишком строгий gate»
   опасен в проде?
3. Добавьте в canary-стратегию шаг `setCanaryScale: {replicas: 1}` перед
   первым setWeight и посмотрите, как изменится поведение.
4. Переведите `demo-rollout-bg` в авторежим (`autoPromotionEnabled: true`,
   `autoPromotionSeconds: 30`) и прокатите релиз без рук.
5. Сломайте и почините релиз по сценарию `broken/scenario-01/` (не подглядывая
   в решение сразу).

---

## Проверка модуля

```bash
bash verify/verify.sh
# [OK] оба Rollout здоровы
# [OK] canary-релиз с анализом доехал до Healthy, AnalysisRun Successful
# [OK] module 24 verified
```

Уборка:

```bash
../../scripts/clean/clean-module.sh modules/24-progressive-delivery
verify/cleanup.sh   # сносит контроллер argo-rollouts
```

---

## Шпаргалка

```bash
kubectl argo rollouts get rollout NAME -n lab --watch   # живой статус
kubectl argo rollouts set image NAME app=IMG -n lab     # запустить релиз
kubectl argo rollouts promote NAME -n lab               # пройти паузу/переключить BG
kubectl argo rollouts abort NAME -n lab                 # откатить на stable
kubectl argo rollouts retry rollout NAME -n lab         # повторить после abort/Degraded
kubectl argo rollouts undo NAME -n lab                  # откат на прошлую ревизию
kubectl -n lab get analysisrun                          # история анализов
kubectl argo rollouts dashboard                         # локальный UI (порт 3100)
```

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Роль |
|--------|-----|------|
| `demo-rollout` | Rollout (canary) | 5 шагов: 25% → 50% → ручная пауза → 100% + фоновый анализ |
| `demo-rollout-svc` | Service | общий сервис canary-приложения |
| `success-rate` | AnalysisTemplate | настоящий Prometheus-gate: доля Ready-подов ≥ 0.9 |
| `demo-rollout-bg` | Rollout (blueGreen) | autoPromotionEnabled: false — ручное переключение |
| `rollout-active` / `rollout-preview` | Service | прод-трафик / превью новой версии (порт 80 → 8080) |
| `argo-rollouts` | ns + controller v1.9.0 | ставится/сносится verify/prepare.sh / cleanup.sh |

## Чему вы научились

- Управлять релизом как процессом: шаги, паузы, promote/abort/retry/undo.
- Строить self-defending релизы: Prometheus-анализ, failureLimit vs
  consecutiveErrorLimit, автоматический откат без участия человека.
- Гонять Blue/Green с превью и атомарным переключением селектора Service.
- Выбирать между Argo Rollouts и Flagger по экосистеме и требованиям к трафику.

## Уборка

```bash
../../scripts/clean/clean-module.sh modules/24-progressive-delivery
verify/cleanup.sh
```
