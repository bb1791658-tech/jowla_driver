#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f config/production.json ]]; then
  echo "config/production.json is missing. Copy production.example.json and fill the real values." >&2
  exit 1
fi

exec flutter run --release --dart-define-from-file=config/production.json "$@"
