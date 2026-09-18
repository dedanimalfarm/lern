# 02-metrics-server-top

## Задача
Проверить текущую нагрузку по node/pod.

## Команды
```bash
kubectl top nodes
kubectl top pods -n lab
```
## Ожидаемый результат
- `kubectl top nodes` показывает три ноды стенда с CPU/RAM; `top pods -n lab` — поды
  модуля. Если ответ `Metrics API not available` — не установлен metrics-server
  (`scripts/bootstrap/02-install-metrics-server.sh`).
- Вы сопоставили `top pods` с `requests` из манифеста и назвали поды, которые
  используют меньше половины своей брони (кандидаты на rightsizing).
