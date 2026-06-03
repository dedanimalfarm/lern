# 04 — Vault dynamic secrets (VSO)
Vault database-engine генерит НОВОГО postgres-юзера на каждый запрос (TTL).
VaultDynamicSecret (VSO) логинится в Vault (k8s auth) и кладёт динамические креды в
k8s Secret, ротируя их. Креды нигде не хранятся постоянно.
