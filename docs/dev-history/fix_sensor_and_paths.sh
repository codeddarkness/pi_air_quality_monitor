#!/usr/bin/env bash
# =============================================================================
# fix_sensor_and_paths.sh v0.2.2
# - Fix sensor_online() to check /dev/ttyUSB0 directly, not just dmesg
# - Create backward-compat symlink at repo root for crontab/bashrc
# - Update crontab to use new script path
# - Force docker image rebuild with --no-cache to pick up template changes
# - Verify /api/ returns live data
# =============================================================================

set -euo pipefail
REPO="${HOME}/pi_air_quality_monitor"
FUNC="${REPO}/scripts/service/aqi_monitor.func"
FUNC_ROOT="${REPO}/aqi_monitor.func"

cd "${REPO}"
log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "[\033[0;32mOK\033[0m] $*"; }
warn(){ echo -e "[\033[0;33mWARN\033[0m] $*"; }

# ── 1. Fix sensor_online() in aqi_monitor.func ───────────────────────────────
# Old logic: dmesg grep only — fails if sensor was plugged in before boot
# New logic: check /dev/ttyUSBx directly first, fall back to dmesg for name
log "Patching sensor_online() in aqi_monitor.func..."
cp "${FUNC}" "${FUNC}.bak.$(date +%Y%m%d%H%M%S)"

# Replace the sensor_online function body with a robust version
python3 - << 'PYEOF'
import re, sys

path = "${PAQM_DIR}/scripts/service/aqi_monitor.func"
with open(path) as f:
    content = f.read()

old_fn = r'function sensor_online\(\)\{.*?^\}.*?# END OF sensor_online'
new_fn = '''function sensor_online(){
# Check device exists directly — dmesg check fails if sensor was present at boot
local dev_port=""
for candidate in /dev/ttyUSB0 /dev/ttyUSB1 /dev/myUSB; do
    if [[ -e "${candidate}" ]]; then
        dev_port="${candidate}"
        break
    fi
done
if [[ -z "${dev_port}" ]]; then
    echo "ERROR:DEVICE NOT FOUND : SDS011 Particulate Matter Sensor"
    return 2>/dev/null || exit
fi
echo " - SDS011 Particulate Matter Sensor CONNECTED : ${dev_port}"
# Export for docker-compose device mapping if non-default path
export SENSOR_DEV="${dev_port}"
}	# END OF sensor_online'''

result = re.sub(old_fn, new_fn, content, flags=re.DOTALL|re.MULTILINE)
if result == content:
    print("WARN: pattern not matched — writing direct replacement")
    # Direct string replacement fallback
    marker_start = 'function sensor_online(){'
    marker_end = '}	# END OF sensor_online'
    start = content.find(marker_start)
    end = content.find(marker_end) + len(marker_end)
    if start == -1:
        print("ERROR: could not find sensor_online function")
        sys.exit(1)
    result = content[:start] + new_fn + content[end:]

with open(path, 'w') as f:
    f.write(result)
print("OK: sensor_online() patched")
PYEOF

ok "sensor_online() patched"

# ── 2. Create symlink at repo root for crontab/bashrc compatibility ───────────
log "Creating backward-compat symlink at repo root..."
if [[ -L "${FUNC_ROOT}" ]]; then
    rm "${FUNC_ROOT}"
fi
if [[ -f "${FUNC_ROOT}" && ! -L "${FUNC_ROOT}" ]]; then
    mv "${FUNC_ROOT}" "${FUNC_ROOT}.old.$(date +%Y%m%d%H%M%S)"
fi
ln -s "${FUNC}" "${FUNC_ROOT}"
ok "Symlink: ${FUNC_ROOT} -> ${FUNC}"

# ── 3. Update crontab paths ───────────────────────────────────────────────────
log "Updating crontab..."
CURRENT_CRON=$(crontab -l 2>/dev/null || true)
NEW_CRON=$(echo "${CURRENT_CRON}" | sed \
    -e 's|${PAQM_DIR}/aqi_monitor.func|${PAQM_DIR}/scripts/service/aqi_monitor.func|g' \
    -e 's|${PAQM_DIR}/run_reformatter.sh|${PAQM_DIR}/scripts/data/run_reformatter.sh|g' \
    -e 's|${PAQM_DIR}/reset_counter.sh|${PAQM_DIR}/scripts/service/reset_counter.sh|g'
)
echo "${NEW_CRON}" | crontab -
ok "Crontab updated"
crontab -l | grep -v '^#' | grep -v '^$'

# ── 4. Ensure .bashrc sources the right aqi_monitor.func ─────────────────────
log "Checking .bashrc source path..."
BASHRC="${HOME}/.bashrc"
# Remove any old direct source lines for aqi_monitor.func
if grep -q 'aqi_monitor.func' "${BASHRC}"; then
    # Update to new path if old path present
    sed -i 's|source ~/pi_air_quality_monitor/aqi_monitor.func|source ~/pi_air_quality_monitor/scripts/service/aqi_monitor.func|g' "${BASHRC}"
    sed -i 's|\. ~/pi_air_quality_monitor/aqi_monitor.func|\. ~/pi_air_quality_monitor/scripts/service/aqi_monitor.func|g' "${BASHRC}"
    ok ".bashrc source path updated"
else
    warn ".bashrc: no aqi_monitor.func source line found — using symlink fallback"
fi

# ── 5. Verify /dev/ttyUSB0 on host ───────────────────────────────────────────
log "Checking sensor on host..."
if ls /dev/ttyUSB* 2>/dev/null; then
    ok "Sensor device present"
else
    warn "/dev/ttyUSB* not found — sensor may be unplugged or needs udev rule"
    echo "  Run: dmesg | grep -i usb | tail -10"
fi

# ── 6. Force rebuild with --no-cache to pick up template changes ──────────────
log "Stopping current stack..."
aqi_monitor stop 2>/dev/null || docker-compose down 2>/dev/null || true
sleep 3

log "Force rebuilding image (--no-cache to pick up index.html changes)..."
docker-compose build --no-cache

log "Starting stack..."
docker-compose up -d
sleep 8

# ── 7. Verify ─────────────────────────────────────────────────────────────────
log "Verifying..."
docker ps | grep -E 'pi-air|redis'

log "Testing API..."
API_RESPONSE=$(curl -s http://localhost:8000/api/ 2>/dev/null || echo "FAIL")
if echo "${API_RESPONSE}" | grep -q '"labels"'; then
    READING_COUNT=$(echo "${API_RESPONSE}" | python3 -c \
        "import json,sys; d=json.load(sys.stdin); print(len(d['historical']['labels']))" 2>/dev/null || echo "?")
    ok "API responding — ${READING_COUNT} historical readings in Redis"
else
    warn "API not responding yet — may need 60s for first sensor reading"
    echo "  Watch: docker-compose logs -f web"
fi

log "Testing page template version..."
PAGE=$(curl -s http://localhost:8000/ 2>/dev/null || echo "")
if echo "${PAGE}" | grep -q 'setInterval\|POLL_INTERVAL'; then
    ok "New auto-refresh template confirmed in use"
elif echo "${PAGE}" | grep -q '0.2.1'; then
    ok "New template version tag found"
else
    warn "Page may still be serving old template — check:"
    echo "  curl -s http://localhost:8000/ | grep -i 'setInterval\|version'"
fi

# ── 8. Reload aqi_monitor in current shell ────────────────────────────────────
log "Reloading aqi_monitor.func in current shell..."
source "${FUNC}"
aqi_monitor status

# ── 9. Commit ─────────────────────────────────────────────────────────────────
log "Committing fixes..."
git add -A
git commit -m "fix(v0.2.2): sensor detection, path compat, template rebuild

- sensor_online(): check /dev/ttyUSBx directly, not just dmesg
  (dmesg check fails when sensor is present at boot time)
- Add backward-compat symlink: repo-root/aqi_monitor.func -> scripts/service/
- Update crontab paths to scripts/service/ and scripts/data/
- Force --no-cache rebuild to pick up index.html template changes
- Export SENSOR_DEV for docker device mapping flexibility" 2>/dev/null || true

git push origin custom_dev 2>/dev/null || warn "Push failed — run: git push origin custom_dev"

echo
echo "======================================================================"
echo "  v0.2.2 applied"
echo "  Sensor  : $(ls /dev/ttyUSB* 2>/dev/null | head -1 || echo 'not found')"
echo "  Web UI  : http://$(hostname -I | awk '{print $1}'):8000"
echo "  API     : http://$(hostname -I | awk '{print $1}'):8000/api/"
echo "  Logs    : tail -f /tmp/sensor_logs/aqi_monitor.log"
echo "  Template: curl -s http://localhost:8000/ | grep setInterval"
echo "======================================================================"
