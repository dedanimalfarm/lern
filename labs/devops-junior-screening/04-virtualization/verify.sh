#!/usr/bin/env bash
set -euo pipefail

echo "==> Running verification for 04-virtualization"

echo "-> Checking Docker installation..."
if ! command -v docker >/dev/null; then
    echo "ERROR: docker is not installed"
    exit 1
fi

if docker info 2>/dev/null | grep -qi "snap"; then
    echo "WARNING: Docker snap installation detected."
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running or user does not have permissions"
    exit 1
fi

echo "-> Checking lab files..."
DIR="$HOME/lab04"
if [[ ! -d "$DIR" ]]; then
    echo "ERROR: Lab directory $DIR not found. Did you complete the steps?"
    exit 1
fi

for f in app/app.py app/Dockerfile compose.yml proxy.conf; do
    if [[ ! -f "$DIR/$f" ]]; then
        echo "ERROR: Expected file $DIR/$f not found"
        exit 1
    fi
done

echo "-> Checking docker image..."
if ! docker image inspect lab04/app:1.0.0 >/dev/null 2>&1; then
    echo "ERROR: Docker image lab04/app:1.0.0 not found. Did you build it?"
    exit 1
fi

echo "-> Checking Docker Compose configuration..."
if ! docker compose -f "$DIR/compose.yml" config >/dev/null 2>&1; then
    echo "ERROR: docker compose config validation failed"
    exit 1
fi

echo "==> Verification passed!"
