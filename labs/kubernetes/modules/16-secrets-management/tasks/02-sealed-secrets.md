# 02 — Sealed Secrets
kubeseal шифрует Secret -> SealedSecret (git-safe). Контроллер расшифровывает в обычный
Secret. SealedSecret привязан к КЛАСТЕРУ (на другом не развернётся — by design).
