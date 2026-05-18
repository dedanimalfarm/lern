#!/usr/bin/env bash
# Понижаем мягкий лимит до 1024 (стандарт для многих дистрибутивов),
# чтобы пример точно упал даже на тачках с уже поднятым ulimit.
ulimit -Sn 1024

echo "Запускаем процесс, пытающийся открыть 5000 файлов (ulimit -n = $(ulimit -n)) ..."

python3 - <<'EOF'
import os, tempfile
opened = []
try:
    for i in range(5000):
        f = open(f"/tmp/open_many_{i}.tmp", "w")
        opened.append(f)
    print(f"Открыто {len(opened)} файлов — лимит не достигнут")
except OSError as e:
    print(f"Открыто {len(opened)} файлов, дальше упало: {e}")
finally:
    for f in opened:
        f.close()
        try: os.unlink(f.name)
        except OSError: pass
EOF
