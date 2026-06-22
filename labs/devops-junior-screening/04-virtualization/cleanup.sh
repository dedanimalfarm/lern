#!/usr/bin/env bash
set -euo pipefail

echo "==> Running cleanup for 04-virtualization"

echo "-> Stopping and removing all containers..."
if [[ $(docker ps -aq) ]]; then
    docker stop $(docker ps -aq) || true
    docker rm -f $(docker ps -aq) || true
fi

echo "-> Removing all Docker volumes..."
if [[ $(docker volume ls -q) ]]; then
    docker volume rm $(docker volume ls -q) || true
fi

echo "-> Pruning Docker system..."
docker system prune -af --volumes || true

echo "-> Removing lab directory..."
DIR="$HOME/lab04"
if [[ -d "$DIR" ]]; then
    rm -rf "$DIR"
fi

echo "==> Cleanup complete!"
