#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"
count_file="${REPO_DIR}/last_count.runs"
[[ -e "${count_file}" ]] || echo 0 > ${count_file}
counter=$(cat ${count_file})
counter=$((counter+1))
echo "${counter}" > ${count_file}

mkdir -p /tmp/sensor_logs
log_file=/tmp/sensor_logs/aqi_mon_reformat.log
touch ${log_file}
(time bash -xv  "${REPO_DIR}/scripts/data/reformat_aqi_data.sh" 2>&1) >> ${log_file} 2>/dev/null ;
echo "$(date) reformat_aqi_data.sh ran ${counter}" >> ${log_file}
