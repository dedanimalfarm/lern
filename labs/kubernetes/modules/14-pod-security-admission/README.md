# Лабораторная работа 14: Pod Security и Admission Control (PSA + ValidatingAdmissionPolicy)

Цель: научиться запрещать небезопасные поды НА ВХОДЕ (admission), пока они не
попали в кластер — через встроенный Pod Security Admission (профили
privileged/baseline/restricted) и ValidatingAdmissionPolicy (кастомные правила на
CEL). К концу модуля вы включаете restricted на namespace, читаете отказ
admission и пишете свою политику без установки внешних движков.

> Всё в этом модуле — **встроено в Kubernetes** (PSA GA с 1.25, VAP GA с 1.30),
> доп. установки не требуется. Kyverno/OPA — только для сложных кейсов (обзор в
> Части 3).

---

## Предварительные требования

```bash
kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab
kubectl delete ns lab-restricted --ignore-not-found 2>/dev/null
kubectl version -o json 2>/dev/null | grep -i gitVersion | head -1   # нужен >=1.30 для VAP
```

---

## Часть 1: Pod Security Admission (PSA)

### Теория для изучения перед частью

- **Pod Security Standards** — три профиля: `privileged` (без ограничений),
  `baseline` (запрет явно опасного), `restricted` (жёстко: non-root, drop caps,
  seccomp, no privilege escalation).
- **PSA** применяет профиль на уровне **namespace** через labels:
  `pod-security.kubernetes.io/enforce|warn|audit: <profile>`. `enforce`
  блокирует, `warn` предупреждает пользователя, `audit` пишет в audit-log.
- Проверка идёт на **admission** (до записи в etcd) — нарушающий под просто не
  создаётся.

---

**Цель:** включить restricted и увидеть, что проходит, а что отклоняется.

**Ресурсы:** `manifests/restricted-ns.yaml`, `good-pod.yaml`,
`broken/scenario-01/bad-pod.yaml`.

---

### 1.1 restricted: good проходит, bad отклоняется

```bash
kubectl apply -f manifests/restricted-ns.yaml
kubectl get ns lab-restricted -o jsonpath='{.metadata.labels}{"\n"}'
# ...enforce:restricted, warn:restricted, audit:restricted

# Соответствующий под (non-root, drop ALL, seccomp) — ПРОХОДИТ
kubectl apply -f manifests/good-pod.yaml
kubectl -n lab-restricted get pod good-pod
# good-pod   1/1   Running

# Нарушающий под (root-образ без securityContext) — ОТКЛОНЁН admission'ом
kubectl apply -f broken/scenario-01/bad-pod.yaml
# Error from server (Forbidden): error when creating "bad-pod.yaml":
#   pods "bad-pod" is forbidden: violates PodSecurity "restricted:latest":
#   allowPrivilegeEscalation != false, unrestricted capabilities,
#   runAsNonRoot != true, seccompProfile ...
```

> Под `bad-pod` даже не создаётся — PSA отклонил его на входе. Это сильнее, чем
> `securityContext` в самом поде (там под создаётся, и kubelet может его уронить);
> PSA не пускает несоответствие в принципе.

**Контрольные вопросы:**
1. Три профиля Pod Security Standards — чем отличаются?
2. Чем `enforce` отличается от `warn`/`audit`?
3. На каком этапе PSA отклоняет под и почему это лучше, чем падение в рантайме?

---

## Часть 2: ValidatingAdmissionPolicy (CEL)

### Теория для изучения перед частью

- **ValidatingAdmissionPolicy (VAP)** — встроенный механизм кастомных правил на
  языке **CEL**, без внешнего webhook-сервера. Состоит из `ValidatingAdmissionPolicy`
  (что проверять) + `...Binding` (где применять, с каким действием).
- `validationActions`: `Deny` (блок), `Warn`, `Audit`.
- Заменяет простые validating-webhooks: быстрее, надёжнее (нет внешнего сервиса),
  декларативно.

---

**Цель:** запретить образы `:latest` в namespace `lab`.

**Ресурс:** `manifests/vap-no-latest.yaml`.

---

### 2.1 Запрет :latest

```bash
kubectl apply -f manifests/vap-no-latest.yaml
kubectl get validatingadmissionpolicy no-latest-tag

# Под с :latest в lab — ОТКЛОНЁН политикой:
kubectl -n lab run bad --image=nginx:latest --restart=Never
# error: ... образы с тегом ':latest' или без тега запрещены — пиньте конкретную версию

# Под с конкретным тегом — проходит:
kubectl -n lab run good --image=nginx:1.27-alpine --restart=Never
kubectl -n lab delete pod good --ignore-not-found
```

> CEL-выражение `object.spec.containers.all(c, c.image.contains(':') &&
> !c.image.endsWith(':latest'))` проверяет каждый контейнер. Так одной декларацией
> закрывается распространённый антипаттерн `:latest` (невоспроизводимые деплои).

**Контрольные вопросы:**
1. Из каких двух объектов состоит VAP и зачем разделение policy/binding?
2. Чем VAP лучше внешнего validating-webhook?
3. Какие `validationActions` бывают и когда `Warn` вместо `Deny`?

---

## Часть 3: Policy engines (Kyverno / OPA Gatekeeper) — обзор

### Теория для изучения перед частью

- Встроенных PSA + VAP хватает для запретов (validate). Когда нужно **мутировать**
  (доставить securityContext по умолчанию), **генерировать** (NetworkPolicy на
  каждый namespace) или **отчёты о соответствии** — берут policy-engine.
- **Kyverno** — политики как YAML (validate/mutate/generate), близок к k8s-стилю.
  **OPA Gatekeeper** — на языке Rego, мощнее, но круче порог входа. Оба ставятся
  через Helm и работают как admission-webhook.

---

```bash
# Установка Kyverno (пример, требует нод и Helm):
# helm repo add kyverno https://kyverno.github.io/kyverno/
# helm install kyverno kyverno/kyverno -n kyverno --create-namespace
# затем применять ClusterPolicy (пример — в tasks/03-policy-engines.md)
```

**Контрольные вопросы:**
1. Когда встроенных PSA/VAP недостаточно и нужен Kyverno/Gatekeeper?
2. Чем Kyverno отличается от OPA Gatekeeper по языку политик?
3. Что такое mutate/generate-политики и зачем они?

---

## Часть 4: Troubleshooting

### Инцидент 1: под отклонён PSA (restricted)

Разобран в `broken/scenario-01/`. Симптом: `apply` падает с
`violates PodSecurity "restricted"`. Диагностика — прочитать, КАКИЕ требования
нарушены (в тексте ошибки перечислены), привести `securityContext` в
соответствие (см. `good-pod.yaml`). Профилактика: собирать под restricted с
самого начала; включать `warn` на namespace, чтобы видеть нарушения заранее.

### Инцидент 2: легитимный под не создаётся из-за VAP

```bash
# Если VAP слишком строга и режет нужное — посмотреть, какая политика сработала:
kubectl -n lab run x --image=nginx:latest --restart=Never 2>&1 | tail -1
# (сообщение из .spec.validations[].message). Лечение: уточнить CEL-выражение
# или сузить binding (matchResources), либо validationActions: Warn вместо Deny.
```

### Инцидент 3: PSA «не срабатывает»

```bash
# Частая причина — опечатка в label или профиль privileged. Проверить:
kubectl get ns lab-restricted -o jsonpath='{.metadata.labels}{"\n"}'
# должно быть pod-security.kubernetes.io/enforce: restricted (точное имя ключа!)
```

**Контрольные вопросы:**
1. Как прочитать из ошибки PSA, ЧТО именно нарушено?
2. Под отклонён VAP — где взять причину и как ослабить политику?
3. PSA «молчит» — две частые причины?

---

## Проверка модуля

```bash
kubectl apply -f manifests/restricted-ns.yaml
kubectl apply -f manifests/good-pod.yaml
kubectl apply -f manifests/vap-no-latest.yaml

bash verify/verify.sh
# [OK] PSA restricted enforced + good-pod Running + VAP no-latest present
# [OK] module 14 verified
```

`verify.sh`: namespace `lab-restricted` существует и `enforce=restricted` →
`good-pod` (соответствующий) Running → `ValidatingAdmissionPolicy/no-latest-tag`
установлена.

---

## Финальная карта ресурсов модуля

| Ресурс | Механизм | Что демонстрирует |
|--------|----------|-------------------|
| `lab-restricted` (ns) | Pod Security Admission | enforce restricted на namespace |
| `good-pod` | — | под, соответствующий restricted (проходит) |
| `bad-pod` (broken) | — | нарушение restricted → отклонён admission |
| `no-latest-tag` | ValidatingAdmissionPolicy (CEL) | запрет `:latest` без внешних движков |

---

## Теоретические вопросы (итоговые)

1. Опишите три профиля Pod Security Standards и три режима PSA.
2. Почему отклонение на admission лучше, чем падение пода в рантайме?
3. Чем `securityContext` в поде отличается от PSA на namespace?
4. Из чего состоит ValidatingAdmissionPolicy и чем она лучше webhook?
5. Когда встроенных средств мало и нужен Kyverno/Gatekeeper?

---

## Шпаргалка

```bash
# === Pod Security Admission ===
kubectl label ns <ns> pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl label ns <ns> pod-security.kubernetes.io/warn=restricted --overwrite
kubectl get ns <ns> -o jsonpath='{.metadata.labels}'
# проверить «сухим прогоном», что пройдёт под профилем:
kubectl label --dry-run=server ns <ns> pod-security.kubernetes.io/enforce=restricted

# === ValidatingAdmissionPolicy ===
kubectl get validatingadmissionpolicy
kubectl get validatingadmissionpolicybinding
kubectl describe validatingadmissionpolicy no-latest-tag

# === Уборка ===
kubectl delete -f manifests/vap-no-latest.yaml
kubectl delete ns lab-restricted --ignore-not-found
```

---

## Уборка

```bash
kubectl delete -f manifests/vap-no-latest.yaml --ignore-not-found
kubectl delete ns lab-restricted --ignore-not-found
```
