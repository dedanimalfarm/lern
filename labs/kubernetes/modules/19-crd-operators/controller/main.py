#!/usr/bin/env python3
"""Entrypoint. Запускается как в поде (in-cluster), так и локально."""
from webapp_controller import main

if __name__ == "__main__":
    raise SystemExit(main())
