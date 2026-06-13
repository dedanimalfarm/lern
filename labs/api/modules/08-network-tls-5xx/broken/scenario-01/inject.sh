#!/usr/bin/env bash
# Слепая диагностика 5xx: включает СЛУЧАЙНУЮ серверную поломку из четырёх.
# Фактический режим прячется в /tmp/api-lab/.m08-actual для check.sh —
# НЕ подглядывайте (и в _lab/state тоже: в реальном инциденте его нет).
#
# Ваша задача — по поведению ОТВЕТА (код, Content-Type, тело, заголовки,
# поведение в серии) понять, какой именно отказ перед вами:
#   error502 | error503 | error504 | flaky
set -euo pipefail

MODES=(error502 error503 error504 flaky)
MODE=${MODES[RANDOM % ${#MODES[@]}]}

curl -s -X POST http://localhost:8080/api/v1/_lab/fault \
  -H 'Content-Type: application/json' -d "{\"mode\":\"$MODE\"}" >/dev/null

mkdir -p /tmp/api-lab
echo "$MODE" > /tmp/api-lab/.m08-actual

cat <<EOF
[OK] серверная поломка включена. Диагностируйте, НЕ заглядывая в _lab/state!
     Различайте по: коду, Content-Type (наш JSON vs html балансировщика),
     заголовку Retry-After и поведению в СЕРИИ запросов.
     Диагноз (error502|error503|error504|flaky) — первой строкой в
     /tmp/api-lab/m08-5xx-diagnosis.txt
     Затем: bash $(dirname "$0")/check.sh
EOF
