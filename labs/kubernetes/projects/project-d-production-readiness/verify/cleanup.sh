#!/usr/bin/env bash
set -euo pipefail

kubectl -n lab delete secret shop-db --ignore-not-found=true
