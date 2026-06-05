#!/usr/bin/env bash
set -euo pipefail

kubectl -n lab create secret generic shop-db --from-literal=password='S3cr3tP@ss' --dry-run=client -o yaml | kubectl apply -f -
