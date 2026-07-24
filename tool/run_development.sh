#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

detect_lan_ip() {
  local default_interface
  default_interface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}' || true)"

  if [[ -n "${default_interface}" ]]; then
    ifconfig "${default_interface}" 2>/dev/null \
      | awk '/inet / && $2 !~ /^127\./ {print $2; exit}'
    return
  fi

  ifconfig 2>/dev/null \
    | awk '/inet / && ($2 ~ /^192\.168\./ || $2 ~ /^10\./ || $2 ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) {print $2; exit}'
}

targets_android_emulator() {
  local previous_was_device_flag=false
  for arg in "$@"; do
    if [[ "${previous_was_device_flag}" == true ]]; then
      [[ "${arg}" == emulator-* ]] && return 0
      previous_was_device_flag=false
    fi

    case "${arg}" in
      -d|--device-id)
        previous_was_device_flag=true
        ;;
      -d=emulator-*|--device-id=emulator-*|emulator-*)
        return 0
        ;;
    esac
  done
  return 1
}

backend_origins="${BACKEND_ORIGINS:-}"
if [[ -z "${backend_origins}" && -n "${BACKEND_ORIGIN:-}" ]]; then
  backend_origins="${BACKEND_ORIGIN}"
fi

if [[ -z "${backend_origins}" ]]; then
  lan_ip="$(detect_lan_ip)"
  if targets_android_emulator "$@"; then
    backend_origins="http://10.0.2.2:3000,http://localhost:3000"
    if [[ -n "${lan_ip}" ]]; then
      backend_origins="${backend_origins},http://${lan_ip}:3000"
    fi
  else
    if [[ -n "${lan_ip}" ]]; then
      backend_origins="http://${lan_ip}:3000,"
    fi
    backend_origins="${backend_origins}http://localhost:3000,http://10.0.2.2:3000"
  fi
fi

flutter_args=(--dart-define-from-file=config/development.json)
if [[ -n "${backend_origins}" ]]; then
  echo "Trying Jowla backends: ${backend_origins}"
  flutter_args+=(--dart-define=BACKEND_ORIGINS="${backend_origins}")
else
  echo "Using app backend fallback. Set BACKEND_ORIGIN if this device cannot reach localhost."
fi

exec flutter run "${flutter_args[@]}" "$@"
