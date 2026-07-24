#!/usr/bin/env bash

set -euo pipefail

maps_dir="$(cd "$(dirname "$0")" && pwd)"
pbf_file="${maps_dir}/data/iraq-latest.osm.pbf"
geocoding_data_dir="${maps_dir}/geocoding-data"
geocoding_pbf="${geocoding_data_dir}/iraq-latest.osm.pbf"

if [[ ! -s "${pbf_file}" ]]; then
  echo "ملف العراق غير موجود. شغّل ./maps/bootstrap.sh أولًا." >&2
  exit 1
fi

mkdir -p "${geocoding_data_dir}"
if [[ ! -s "${geocoding_pbf}" || "${pbf_file}" -nt "${geocoding_pbf}" ]]; then
  cp "${pbf_file}" "${geocoding_pbf}.next"
  mv "${geocoding_pbf}.next" "${geocoding_pbf}"
fi

docker compose \
  --file "${maps_dir}/docker-compose.yml" \
  --profile geocoding \
  up --detach geocoding

echo "بدأ استيراد بحث عناوين العراق المحلي."
echo "تابع التقدم: docker compose -f maps/docker-compose.yml logs -f geocoding"
echo "بعد اكتماله: http://localhost:7070/search?q=بغداد&format=jsonv2"
