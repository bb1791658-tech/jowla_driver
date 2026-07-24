#!/usr/bin/env bash

set -euo pipefail

maps_dir="$(cd "$(dirname "$0")" && pwd)"
data_dir="${maps_dir}/data"
iraq_pbf="${data_dir}/iraq-latest.osm.pbf"
tiles_file="${data_dir}/iraq.mbtiles"
style_archive="${data_dir}/versatiles-styles-v5.13.0.tar.gz"
vendor_styles_dir="${data_dir}/vendor-styles"
generated_styles_dir="${data_dir}/styles"

mkdir -p "${data_dir}"

if [[ ! -e "${data_dir}/current" ]]; then
  ln -s . "${data_dir}/current"
fi

if [[ ! -s "${tiles_file}" ]]; then
  download_file="${tiles_file}.download"
  curl --fail --location --retry 3 \
    --output "${download_file}" \
    https://download.geofabrik.de/asia/iraq-shortbread-1.0.mbtiles
  mv "${download_file}" "${tiles_file}"
fi

if [[ ! -s "${style_archive}" ]]; then
  download_file="${style_archive}.download"
  curl --fail --location --retry 3 \
    --output "${download_file}" \
    https://github.com/versatiles-org/versatiles-style/releases/download/v5.13.0/styles.tar.gz
  mv "${download_file}" "${style_archive}"
fi

if [[ ! -s "${vendor_styles_dir}/colorful/style.json" ]]; then
  mkdir -p "${vendor_styles_dir}"
  tar -xzf "${style_archive}" \
    -C "${vendor_styles_dir}" \
    colorful/style.json
fi

"${maps_dir}/prepare_assets.sh"

node "${maps_dir}/prepare_styles.mjs" \
  "${vendor_styles_dir}" \
  "${generated_styles_dir}"

if [[ ! -s "${iraq_pbf}" ]]; then
  download_file="${iraq_pbf}.download"
  curl --fail --location --retry 3 \
    --output "${download_file}" \
    https://download.geofabrik.de/asia/iraq-latest.osm.pbf
  mv "${download_file}" "${iraq_pbf}"
fi

if [[ ! -s "${data_dir}/iraq-latest.osrm.partition" ]]; then
  docker run --rm -v "${data_dir}:/data" \
    ghcr.io/project-osrm/osrm-backend:latest \
    osrm-extract -p /opt/car.lua /data/iraq-latest.osm.pbf
  docker run --rm -v "${data_dir}:/data" \
    ghcr.io/project-osrm/osrm-backend:latest \
    osrm-partition /data/iraq-latest.osrm
  docker run --rm -v "${data_dir}:/data" \
    ghcr.io/project-osrm/osrm-backend:latest \
    osrm-customize /data/iraq-latest.osrm
fi

docker compose --file "${maps_dir}/docker-compose.yml" up --detach

echo "Jowla Iraq maps: http://localhost:8080"
echo "Jowla Iraq routing: http://localhost:5001/route/v1/driving/..."
