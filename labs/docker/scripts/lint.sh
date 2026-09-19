#!/usr/bin/env bash
set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 1
  fi
}

require_cmd hadolint
require_cmd yamllint
require_cmd shellcheck

# Намеренно «плохие» Dockerfile — учебный материал: файлы из broken/ и ранние
# ступени hardening-lab (stage0..stage2) показывают ровно те антипаттерны,
# которые ловит hadolint. Линтовать их = красить CI на содержимом урока.
# Финальная ступень stage3-runtime-locked проверяется как обычный файл.
is_intentionally_bad() {
  case "$1" in
    */broken/*|*/hardening-lab/stage0-*|*/hardening-lab/stage1-*|*/hardening-lab/stage2-*) return 0 ;;
    *) return 1 ;;
  esac
}

mapfile -t all_dockerfiles < <(find . -type f \( -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' \) ! -path './legacy/*' | sort)
dockerfiles=()
skipped=0
for f in "${all_dockerfiles[@]}"; do
  if is_intentionally_bad "$f"; then
    skipped=$((skipped+1))
    continue
  fi
  dockerfiles+=("$f")
done

mapfile -t yaml_files < <(find . -type f \( -name '*.yaml' -o -name '*.yml' \) ! -path './legacy/*' | sort)
mapfile -t sh_files < <(find . -type f -name '*.sh' ! -path './legacy/*' | sort)

if [[ ${#dockerfiles[@]} -gt 0 ]]; then
  echo "hadolint: ${#dockerfiles[@]} файл(ов), пропущено учебно-битых: $skipped"
  hadolint "${dockerfiles[@]}"
else
  echo "hadolint: no Dockerfiles found"
fi

if [[ ${#yaml_files[@]} -gt 0 ]]; then
  yamllint -c .yamllint.yml "${yaml_files[@]}"
else
  echo "yamllint: no YAML files found"
fi

if [[ ${#sh_files[@]} -gt 0 ]]; then
  shellcheck "${sh_files[@]}"
else
  echo "shellcheck: no shell scripts found"
fi
