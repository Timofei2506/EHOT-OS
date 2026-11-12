#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "[1/4] Проверка синтаксиса bash и shellcheck..."
mapfile -t SH_FILES < <(find . -type f -name '*.sh' -not -path './.git/*' | sort)
for f in "${SH_FILES[@]}"; do
  bash -n "$f"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "${SH_FILES[@]}"
else
  echo "Предупреждение: shellcheck не установлен, пропуск статического анализа."
fi

echo "[2/4] Проверка компиляции всех Python-скриптов..."
mapfile -t PY_FILES < <(find . -type f -name '*.py' -not -path './.git/*' | sort)
python3 -m py_compile "${PY_FILES[@]}"

echo "[3/4] Интеграционный тест GPT-разметки..."
bash tests/test_installer_loopback.sh

echo "[4/4] Запуск pytest..."
pytest -v tests/

echo "ВСЕ ПРОВЕРКИ EHOT OS ПРОЙДЕНЫ УСПЕШНО."
