# Сценарий 02: Application не синхронизируется — destination не разрешён проектом

## Симптом

```bash
kubectl -n argocd get application demo-app-prod
# NAME            SYNC STATUS   HEALTH STATUS
# demo-app-prod   Unknown       Unknown
kubectl -n argocd get application demo-app-prod -o jsonpath='{.status.conditions[*].message}{"\n"}'
# application destination server 'https://kubernetes.default.svc' and namespace 'prod' do not match any of the allowed destinations in project 'labs'
```

## Запуск

```bash
kubectl apply -f gitops/argocd/project.yaml
kubectl apply -f broken/scenario-02/app.yaml
sleep 10; kubectl -n argocd get application demo-app-prod
```

## Задание

1. Прочитайте `status.conditions` Application — это первая точка диагностики любого «Unknown».
2. Найдите, кто именно запрещает: сам Application или AppProject `labs`.
3. Исправьте **правильную** сторону: либо Application, либо проект — и объясните, когда что уместно.

Начните:

```bash
kubectl -n argocd get application demo-app-prod -o jsonpath='{.status.conditions}{"\n"}'
kubectl -n argocd get appproject labs -o jsonpath='{.spec.destinations}{"\n"}'
```

<details>
<summary><strong>Подсказка 1</strong></summary>

Тип условия — `InvalidSpecError`: Argo даже не начинал сравнение с git, спека отвергнута на входе.

</details>

<details>
<summary><strong>Подсказка 2</strong></summary>

AppProject — граница доверия: `spec.destinations` перечисляет, куда проекту можно деплоить. В `labs` разрешён только namespace `lab`.

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- Application объявил `destination.namespace: prod`, а AppProject `labs` разрешает только `lab`.
- Argo CD валидирует Application против проекта до любых действий и выставляет
  `InvalidSpecError`; sync невозможен, HEALTH — `Unknown`.
- Это защита от «случайного прода»: разработчик правит только Application, а расширить
  список destinations может лишь владелец проекта — отдельным изменением и ревью.

</details>

<details>
<summary><strong>Решение</strong></summary>

Для лабораторного приложения правильно исправить Application (namespace `lab`):

```bash
kubectl apply -f solutions/scenario-02/app.yaml
kubectl -n argocd get application demo-app-prod -w      # Synced / Healthy
kubectl -n argocd delete application demo-app-prod       # уборка
```
Если бы `prod` действительно был нужен — добавлять его в `spec.destinations` проекта `labs`,
а не менять политику «под задачу».

</details>
