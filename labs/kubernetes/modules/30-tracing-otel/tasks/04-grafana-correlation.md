# 04-grafana-correlation

## Задача
Подключить Tempo к Grafana (модуль 17) и связать трейсы с логами Loki
(модуль 18) в обе стороны: лог → трейс (derivedFields) и спан → логи
(tracesToLogsV2).

## Команды
```bash
kubectl apply -f manifests/tempo-datasource.yaml -f manifests/loki-datasource-v2.yaml

# Сайдкар Grafana подхватит секреты и дернёт reload (~30-60с):
kubectl -n monitoring logs deploy/kps-grafana -c grafana-sc-datasources --tail=5

# UI:
kubectl -n monitoring port-forward svc/kps-grafana 3909:80 &
# пароль admin:
kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

В Grafana (`http://localhost:3909`):
1. **Explore → Tempo**: TraceQL `{resource.service.name="frontend"}` — открыть
   трейс, в спане backend нажать кнопку **Logs for this span**.
2. **Explore → Loki**: `{app="frontend"} |= "backend answered"` — раскрыть
   строку, рядом с полем TraceID кнопка **«Трейс в Tempo»** (split view).

## Проверка
- `GET /api/datasources` показывает Tempo (uid=tempo) и Loki (uid=loki).
- Ссылки в обе стороны открывают связанные данные по одному trace_id.

## Вопросы
1. Откуда Grafana знает, как из строки лога достать trace_id? (regex derivedFields)
2. Почему uid обоих datasource зафиксированы в provisioning-файлах?
3. Что сломается, если у запровиженного datasource поменять uid «наживую»?
   (reload 500 «data source not found» — лечится deleteDatasources)
