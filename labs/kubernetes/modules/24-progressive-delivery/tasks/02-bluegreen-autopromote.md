# Задание 2: Blue/Green — ручной и автоматический promote

1. Прокатите релиз `demo-rollout-bg` на новый цвет; пока он стоит в
   BlueGreenPause, докажите curl'ом (под curlimages/curl с ЯВНЫМИ resources —
   квота!), что active и preview отдают разные цвета.
2. Посчитайте по `kubectl -n lab get pods`, сколько ёмкости ест переход, и
   сверьтесь с `kubectl -n lab describe quota lab-quota`.
3. Включите `autoPromotionEnabled: true` + `autoPromotionSeconds: 30` и
   прокатите ещё раз — где теперь «точка невозврата»?
4. Добавьте к blueGreen-стратегии `prePromotionAnalysis` с нашим же
   AnalysisTemplate `success-rate` (args: app=demo-rollout-bg). Что изменится
   в порядке событий promote?

<details><summary>Подсказка к п.4</summary>

prePromotionAnalysis гоняет анализ ПРОТИВ preview-версии ДО переключения
active — провал отменяет promote, прод-трафик не страдает вообще.
</details>
