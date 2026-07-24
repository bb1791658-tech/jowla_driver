#!/usr/bin/env bash

set -euo pipefail

maps_dir="$(cd "$(dirname "$0")" && pwd)"
data_dir="${1:-${maps_dir}/data}"
sprites_dir="${data_dir}/sprites/basics"
fonts_dir="${data_dir}/fonts"
asset_origin="https://tiles.versatiles.org/assets"

mkdir -p "${sprites_dir}" "${fonts_dir}"

for suffix in .json .png @2x.json @2x.png; do
  target="${sprites_dir}/sprites${suffix}"
  if [[ ! -s "${target}" ]]; then
    curl --fail --location --retry 3 \
      --output "${target}.download" \
      "${asset_origin}/sprites/basics/sprites${suffix}"
    mv "${target}.download" "${target}"
  fi
done

# النطاقات التي تغطي العربية والكردية واللاتينية وعلامات الترقيم المستخدمة
# في أسماء الأماكن العراقية. يمكن إضافة نطاقات أخرى لاحقًا دون تغيير النمط.
ranges=(
  "0-255"
  "256-511"
  "1536-1791"
  "1792-2047"
  "2048-2303"
  "8192-8447"
  "64256-64511"
  "64512-64767"
  "64768-65023"
  "65024-65279"
  "65280-65535"
)

for font in noto_sans_regular noto_sans_bold; do
  mkdir -p "${fonts_dir}/${font}"
  for range in "${ranges[@]}"; do
    target="${fonts_dir}/${font}/${range}.pbf"
    if [[ ! -s "${target}" ]]; then
      curl --fail --location --retry 3 \
        --output "${target}.download" \
        "${asset_origin}/glyphs/${font}/${range}.pbf"
      mv "${target}.download" "${target}"
    fi
  done
done
