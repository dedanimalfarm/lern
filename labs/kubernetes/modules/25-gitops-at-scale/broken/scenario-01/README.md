# Сценарий 01: ApplicationSet породил «битый» Application — `path does not exist`

## Симптом

```bash
kubectl apply -f broken/scenario-01/appset-broken.yaml
sleep 10
kubectl -n argocd get applications
# NAME           SYNC STATUS   HEALTH STATUS
# web-dev        Synced        Healthy
# web-prod       Synced        Healthy
# web-stagng     Unknown       Healthy       <- SYNC=Unknown: path не найден (битый)
#   ^ health может быть Healthy/Missing (ресурсов нет) — ключевой сигнал именно SYNC=Unknown
```

## Подсказки

1. Откуда взялся `web-stagng`? ApplicationSet создаёт по Application на КАЖДЫЙ
   элемент генератора — посмотри список `elements` в `appset-broken.yaml`.
2. Глянь причину у битого Application:
   `kubectl -n argocd get application web-stagng -o jsonpath='{.status.conditions}'`
   (ищи `ComparisonError` / `app path does not exist`).
3. ApplicationSet НЕ проверяет, существует ли `path` в репозитории. Опечатка в
   генераторе → Application с несуществующим путём.

## Диагностика

```bash
kubectl -n argocd get application web-stagng \
  -o jsonpath='{.status.conditions[*].message}{"\n"}'
# ... overlays/stagng: app path does not exist

# Корень — опечатка в элементе списка генератора:
grep -n 'env:' broken/scenario-01/appset-broken.yaml
#   env: stagng        <-- должно быть staging
```

## Решение

Исправить опечатку в генераторе и переприменить ApplicationSet. ApplicationSet
сам УДАЛИТ Application `web-stagng` (его больше нет в наборе) и создаст `web-staging`:

```bash
kubectl apply -f solutions/01-path/appset-fixed.yaml
sleep 10
kubectl -n argocd get applications
# web-dev / web-staging / web-prod — все Synced/Healthy, web-stagng исчез
```

## Профилактика

- Источник имён окружений — один список; держать его коротким и проверенным.
- Для path-генерации из реальной структуры репо вместо ручного списка используют
  **git directory generator** (Application на каждый каталог `overlays/*`) — тогда
  «несуществующего» окружения в принципе не появится.
- `goTemplateOptions: ["missingkey=error"]` ловит опечатки в ИМЕНАХ полей шаблона
  (но не в значениях вроде `stagng`).
