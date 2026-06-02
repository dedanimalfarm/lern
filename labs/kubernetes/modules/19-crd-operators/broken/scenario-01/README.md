# Сценарий 01: Custom Resource отклонён схемой CRD

## Симптом

`kubectl apply` кастомного ресурса падает с ошибкой валидации — объект не
создаётся.

## Запуск

```bash
kubectl apply -f bad-webapp.yaml
# error: ... spec.replicas: Invalid value: 99: spec.replicas in body should be
#   less than or equal to 10
# и/или: spec.image: Required value
```

## Задание

1. Найдите, какие правила схемы CRD нарушены.
2. Исправьте ресурс и создайте его.

<details>
<summary><strong>Подсказка</strong></summary>

Схема CRD (`openAPIV3Schema`) задаёт типы, обязательные поля (`required`) и
ограничения (`minimum`/`maximum`). apiserver валидирует CR по ней на admission.

```bash
kubectl get crd webapps.lab.example.com -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec}'
```

</details>

<details>
<summary><strong>Объяснение</strong></summary>

- `replicas: 99` нарушает `maximum: 10`.
- Поле `image` обязательно (`required: [image, replicas]`), но отсутствует.
- apiserver отклоняет CR по схеме — расширение API получает валидацию бесплатно.

</details>

<details>
<summary><strong>Решение</strong></summary>

```bash
kubectl apply -f ../../manifests/webapp.yaml   # валидный: image задан, replicas=3
kubectl -n lab get webapp
```

</details>
