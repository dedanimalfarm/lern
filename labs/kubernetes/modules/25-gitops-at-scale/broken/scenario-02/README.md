# Сценарий 02: Все три окружения разом стали `Unknown`

## Симптом

ApplicationSet цел, все три Application на месте — но ни одно не синхронизируется:

```bash
kubectl -n argocd get applications
# NAME          SYNC STATUS   HEALTH STATUS
# web-dev       Unknown       Unknown
# web-prod      Unknown       Unknown
# web-staging   Unknown       Unknown
kubectl -n argocd get application web-dev -o jsonpath='{.status.conditions[*].message}{"\n"}'
# application repo https://github.com/dedanimalfarm/lern.git is not permitted in project 'labs-gitops'
```

## Запуск

```bash
kubectl apply -k applicationset/
kubectl apply -f broken/scenario-02/appproject.yaml
sleep 15; kubectl -n argocd get applications
```

## Задание

1. Три Application сломались одновременно — что у них общее?
2. Найдите объект, который отвечает на вопрос «откуда можно брать манифесты».
3. Исправьте и убедитесь, что все три окружения вернулись в `Synced`.

Начните:

```bash
kubectl -n argocd get appproject labs-gitops -o jsonpath='{.spec.sourceRepos}{"\n"}'
kubectl -n argocd get applicationset web-environments -o jsonpath='{.spec.template.spec.source.repoURL}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

Ошибка одинаковая у всех и приходит от проекта: `InvalidSpecError ... not permitted in project` — это `AppProject`, а не ApplicationSet.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

`spec.sourceRepos` проекта содержит `lern-labs.git`, а ApplicationSet генерирует Application с `lern.git`. Whitelist репозиториев не совпал.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- AppProject — единая граница доверия для всех Application проекта: изменение
  `sourceRepos` мгновенно ломает (или чинит) всё, что в проекте. Поэтому три окружения
  упали синхронно.
- Отличие от сценария 01: там ломался один Application из-за `path`; здесь спека
  всех приложений отвергнута проектом (`InvalidSpecError`), сравнение с git не начинается.
- Правки AppProject — «радиус поражения = все приложения»; их держат под ревью отдельно
  от изменений приложений.

</details>

<details>
<summary><strong>Решение</strong></summary>

Вернуть правильный репозиторий в whitelist — `solutions/scenario-02/appproject.yaml`:

```bash
kubectl apply -f solutions/scenario-02/appproject.yaml
sleep 30; kubectl -n argocd get applications     # Synced / Healthy
```

</details>
