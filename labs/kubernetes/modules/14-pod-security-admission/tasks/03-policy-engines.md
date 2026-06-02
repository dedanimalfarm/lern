# 03-policy-engines

## Задача
Понять, когда хватает встроенных средств, а когда нужен policy-engine.

## Идея
- **Pod Security Admission** — только профили pod-security (быстро, без установки).
- **ValidatingAdmissionPolicy** (CEL, встроена) — кастомные правила валидации.
- **Kyverno / OPA Gatekeeper** — когда нужны mutate/generate, сложная логика,
  отчёты о соответствии. Требуют установки (Helm).

## Пример Kyverno (требует установки)
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: require-requests-limits }
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-resources
    match: { any: [{ resources: { kinds: [Pod] } }] }
    validate:
      message: "requests и limits обязательны"
      pattern:
        spec:
          containers:
          - resources:
              requests: { memory: "?*", cpu: "?*" }
              limits: { memory: "?*" }
```
