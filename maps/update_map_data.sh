#!/usr/bin/env bash

set -euo pipefail

maps_dir="$(cd "$(dirname "$0")" && pwd)"
data_dir="${maps_dir}/data"
releases_dir="${data_dir}/releases"
runtime_dir="${maps_dir}/runtime"
release_id="${1:-$(date -u +%Y%m%dT%H%M%SZ)}"
release_dir="${releases_dir}/${release_id}"
compose_file="${maps_dir}/docker-compose.yml"
active_file="${runtime_dir}/active_slot"
upstreams_file="${runtime_dir}/upstreams.conf"
lock_dir="${data_dir}/.update-lock"
history_file="${data_dir}/update-history.log"
update_status="FAILED"

if ! mkdir "${lock_dir}" 2>/dev/null; then
  echo "يوجد تحديث خرائط آخر قيد التنفيذ." >&2
  exit 1
fi

cleanup() {
  local exit_code="$?"
  rmdir "${lock_dir}" 2>/dev/null || true
  printf '%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${release_id}" "${update_status}" \
    >> "${history_file}"
  if [[ "${exit_code}" -ne 0 && -n "${MAP_UPDATE_ALERT_WEBHOOK:-}" ]]; then
    curl --silent --show-error --fail --max-time 10 \
      -H 'Content-Type: application/json' \
      --data "{\"service\":\"jowla-maps\",\"release\":\"${release_id}\",\"status\":\"failed\"}" \
      "${MAP_UPDATE_ALERT_WEBHOOK}" >/dev/null || true
  fi
}
trap cleanup EXIT

if [[ -e "${release_dir}" ]]; then
  echo "الإصدار موجود مسبقًا: ${release_dir}" >&2
  exit 1
fi

mkdir -p "${release_dir}" "${runtime_dir}"

download() {
  local url="$1"
  local target="$2"
  curl --fail --location --retry 3 \
    --output "${target}.download" \
    "${url}"
  mv "${target}.download" "${target}"
}

echo "1/7 تنزيل بيانات العراق إلى مساحة مرحلية…"
download "https://download.geofabrik.de/asia/iraq-latest.osm.pbf" \
  "${release_dir}/iraq-latest.osm.pbf"
download "https://download.geofabrik.de/asia/iraq-shortbread-1.0.mbtiles" \
  "${release_dir}/iraq.mbtiles"
download "https://github.com/versatiles-org/versatiles-style/releases/download/v5.13.0/styles.tar.gz" \
  "${release_dir}/versatiles-styles-v5.13.0.tar.gz"

echo "2/7 التحقق من سلامة MBTiles…"
if command -v sqlite3 >/dev/null 2>&1; then
  integrity="$(sqlite3 "${release_dir}/iraq.mbtiles" 'PRAGMA quick_check;')"
  [[ "${integrity}" == "ok" ]] || {
    echo "فشل فحص MBTiles: ${integrity}" >&2
    exit 1
  }
fi

echo "3/7 تجهيز التصميم والخطوط والرموز المحلية…"
mkdir -p "${release_dir}/vendor-styles"
tar -xzf "${release_dir}/versatiles-styles-v5.13.0.tar.gz" \
  -C "${release_dir}/vendor-styles" \
  colorful/style.json
node "${maps_dir}/prepare_styles.mjs" \
  "${release_dir}/vendor-styles" \
  "${release_dir}/styles"
"${maps_dir}/prepare_assets.sh" "${release_dir}"
node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" \
  "${release_dir}/styles/jowla-day.json"

echo "4/7 بناء فهرس OSRM في الإصدار المرحلي…"
docker run --rm -v "${release_dir}:/data" \
  ghcr.io/project-osrm/osrm-backend:latest \
  osrm-extract -p /opt/car.lua /data/iraq-latest.osm.pbf
docker run --rm -v "${release_dir}:/data" \
  ghcr.io/project-osrm/osrm-backend:latest \
  osrm-partition /data/iraq-latest.osrm
docker run --rm -v "${release_dir}:/data" \
  ghcr.io/project-osrm/osrm-backend:latest \
  osrm-customize /data/iraq-latest.osrm
[[ -s "${release_dir}/iraq-latest.osrm.partition" ]]

active="$(tr -d '[:space:]' < "${active_file}")"
if [[ "${active}" == "blue" ]]; then
  inactive="green"
else
  inactive="blue"
fi

echo "5/7 تشغيل الإصدار على المسار ${inactive} دون لمس المسار النشط…"
if [[ "${inactive}" == "green" ]]; then
  MAPS_GREEN_DATA="${release_dir}" docker compose \
    --file "${compose_file}" up --detach --no-deps --force-recreate \
    tiles_green routing_green
else
  MAPS_BLUE_DATA="${release_dir}" docker compose \
    --file "${compose_file}" up --detach --no-deps --force-recreate \
    tiles_blue routing_blue
fi

check_inside_network() {
  local url="$1"
  local host_header="${2:-}"
  local attempt
  for attempt in {1..45}; do
    if [[ -n "${host_header}" ]]; then
      if docker run --rm --network jowla-maps_default curlimages/curl:8.16.0 \
        --silent --fail --max-time 5 -H "Host: ${host_header}" "${url}" \
        >/dev/null; then
        return 0
      fi
    elif docker run --rm --network jowla-maps_default curlimages/curl:8.16.0 \
      --silent --fail --max-time 5 "${url}" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

check_inside_network \
  "http://tiles_${inactive}:8080/styles/day/style.json" "localhost"
check_inside_network \
  "http://routing_${inactive}:5000/route/v1/driving/44.3661,33.3152;44.4010,33.3300?overview=false"

echo "6/7 تبديل بوابة الطلبات لحظيًا…"
next_conf="${runtime_dir}/upstreams.conf.next"
sed -E -e "s/tiles_(blue|green)/tiles_${inactive}/g" \
  -e "s/routing_(blue|green)/routing_${inactive}/g" \
  "${upstreams_file}" > "${next_conf}"
cp "${upstreams_file}" "${runtime_dir}/upstreams.conf.previous"
mv "${next_conf}" "${upstreams_file}"
if ! docker compose --file "${compose_file}" exec -T gateway nginx -s reload; then
  mv "${runtime_dir}/upstreams.conf.previous" "${upstreams_file}"
  docker compose --file "${compose_file}" exec -T gateway nginx -s reload
  echo "فشل تبديل البوابة؛ بقي الإصدار السابق نشطًا." >&2
  exit 1
fi

echo "7/7 تثبيت مؤشر الإصدار الحالي بعد نجاح الفحص…"
next_link="${data_dir}/current.next"
rm -f "${next_link}"
ln -s "releases/${release_id}" "${next_link}"
mv "${next_link}" "${data_dir}/current"
printf '%s\n' "${inactive}" > "${active_file}.next"
mv "${active_file}.next" "${active_file}"
printf '%s\n' "${release_id}" > "${data_dir}/current-version.next"
mv "${data_dir}/current-version.next" "${data_dir}/current-version"
update_status="ACTIVE"

echo "تم تفعيل خرائط ${release_id} دون قطع الخدمة."
echo "المسار السابق ${active} باقٍ جاهزًا للرجوع السريع."
