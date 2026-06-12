# Задание 1: Канарейка и метрический gate

1. Прокатите успешный релиз `demo-rollout` (любой цвет из: blue, yellow,
   green, orange) и зафиксируйте: на каком шаге релиз ждал вас, что показывал
   `kubectl -n lab get analysisrun`.
2. Прокатите битый релиз (`:does-not-exist`) и НЕ трогайте его. Засеките,
   через сколько секунд Rollout стал Degraded, и объясните арифметику из
   параметров анализа (initialDelay + interval × (failureLimit+1)).
3. Верните рабочий образ через `set image` + `retry rollout`. Чем этот путь
   отличается от `undo`?
4. Подберите такие `count`/`failureLimit`, чтобы здоровый релиз проходил даже
   при одном случайном провале измерения (flaky Prometheus). Какой ценой?

<details><summary>Подсказка к п.2</summary>

initialDelay 20s + первая неудача ~на 20s, вторая через interval 15s -> abort
примерно на 35-50-й секунде после старта анализа; плюс время на создание
канарейки. На стенде выходило ~1.5 минуты от set image до Degraded.
</details>
