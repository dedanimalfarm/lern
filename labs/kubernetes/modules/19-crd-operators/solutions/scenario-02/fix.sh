#!/usr/bin/env bash
set -euo pipefail
kubectl -n lab patch webapp stuck-webapp --type=merge -p '{"metadata":{"finalizers":null}}'
kubectl -n lab get webapp stuck-webapp 2>&1 | tail -1
