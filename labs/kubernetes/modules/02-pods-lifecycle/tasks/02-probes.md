# 02-probes

## Цель
Увидеть, как probes влияют на доступность через Service.

## Шаги
1. Запустить `manifests/probes`.
2. Применить broken вариант из `broken/scenario-01`.
3. Проверить endpoints и события Pod.
4. Вернуть корректный вариант из `solutions/01-readiness-fail`.

## Проверка
- В broken-сценарии endpoints пустой.
- После fix Pod в статусе Ready.
