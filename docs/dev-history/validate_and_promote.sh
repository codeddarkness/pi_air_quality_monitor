#!/usr/bin/env bash
# =============================================================================
# validate_and_promote.sh v0.3.0
# Run this after all fixes are confirmed working.
# Steps:
#   1. Full validation suite (sensor, docker, API, template, crontab)
#   2. Write install.sh for fresh deployments
#   3. Merge custom_dev → main and tag v1.0.0
# =============================================================================

set -euo pipefail
REPO="${HOME}/pi_air_quality_monitor"
PASS=0; FAIL=0
cd "${REPO}"

log()  { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()   { echo -e "  [\033[0;32mPASS\033[0m] $*"; ((++PASS)); }
fail() { echo -e "  [\033[0;31mFAIL\033[0m] $*"; ((FAIL++)); }
warn() { echo -e "  [\033[0;33mWARN\033[0m] $*"; }
hdr()  { echo; echo -e "\033[1m$*\033[0m"; echo "$(printf '─%.0s' {1..60})"; }

# ═══════════════════════════════════════════════════════════════
# PART 1 — VALIDATION SUITE
# ═══════════════════════════════════════════════════════════════
hdr "1/4  Environment"

[[ -f "${REPO}/Dockerfile" ]]           && ok "Repo directory found"          || fail "Repo not found at ${REPO}"
[[ -f "${REPO}/VERSION" ]]              && ok "VERSION file present: $(cat ${REPO}/VERSION)" || fail "VERSION missing"
command -v docker        &>/dev/null    && ok "docker available"               || fail "docker not installed"
command -v docker-compose &>/dev/null   && ok "docker-compose available"       || fail "docker-compose not installed"
command -v python3       &>/dev/null    && ok "python3 available"              || fail "python3 not installed"
[[ -f "${HOME}/.bashrc" ]] && grep -q 'aqi_monitor' "${HOME}/.bashrc" \
                                        && ok ".bashrc sources aqi_monitor"    || warn ".bashrc: aqi_monitor not sourced (manual source required)"

hdr "2/4  Sensor"

if ls /dev/ttyUSB* &>/dev/null; then
    DEV=$(ls /dev/ttyUSB* | head -1)
    ok "Sensor device: ${DEV}"
else
    fail "No /dev/ttyUSB* — sensor unplugged or udev rule missing"
fi

[[ -f "/etc/udev/rules.d/99_usbdevices.rules" ]] \
    && ok "udev rule present: $(cat /etc/udev/rules.d/99_usbdevices.rules)" \
    || warn "udev rule missing (run scripts/service/set_tty_aqi.sh)"

[[ -L "${REPO}/aqi_monitor.func" ]] \
    && ok "aqi_monitor.func symlink present" \
    || fail "aqi_monitor.func symlink missing at repo root"

hdr "3/4  Docker Stack"

WEB_RUNNING=$(docker ps --filter "name=pi_air_quality_monitor" --filter "name=web" --format "{{.Names}}" 2>/dev/null | head -1)
REDIS_RUNNING=$(docker ps --filter "name=pi_air_quality_monitor" --filter "name=redis" --format "{{.Names}}" 2>/dev/null | head -1)
IMAGE_EXISTS=$(docker images --format "{{.Repository}}" | grep 'pi-air-quality-monitor' || true)

[[ -n "${WEB_RUNNING}" ]]   && ok "Web container running: ${WEB_RUNNING}"   || fail "Web container not running"
[[ -n "${REDIS_RUNNING}" ]] && ok "Redis container running: ${REDIS_RUNNING}" || fail "Redis container not running"
[[ -n "${IMAGE_EXISTS}" ]]  && ok "Docker image built: pi-air-quality-monitor" || fail "Image not built — run: docker-compose build"

hdr "4/4  API & Template"

API=$(curl -sf http://localhost:8000/api/ 2>/dev/null || echo "")
if [[ -n "${API}" ]] && echo "${API}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'historical' in d" 2>/dev/null; then
    COUNT=$(echo "${API}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['historical']['labels']))" 2>/dev/null || echo 0)
    LATEST=$(echo "${API}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['historical']['labels'][-1])" 2>/dev/null || echo "?")
    AQI_LAST=$(echo "${API}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['historical']['aqi']['data'][-1])" 2>/dev/null || echo "?")
    PM10_LAST=$(echo "${API}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['historical']['pm10']['data'][-1])" 2>/dev/null || echo "?")
    PM25_LAST=$(echo "${API}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['historical']['pm2']['data'][-1])" 2>/dev/null || echo "?")
    ok "API /api/ responding — ${COUNT} readings"
    ok "Latest reading: ${LATEST}"
    ok "AQI=${AQI_LAST}  PM10=${PM10_LAST}  PM2.5=${PM25_LAST}  (low values = clean air ✓)"
else
    fail "API /api/ not responding"
fi

NOW_API=$(curl -sf http://localhost:8000/api/now/ 2>/dev/null || echo "")
[[ -n "${NOW_API}" ]] && echo "${NOW_API}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'current' in d" 2>/dev/null \
    && ok "API /api/now/ responding" || fail "API /api/now/ not responding"

PAGE=$(curl -sf http://localhost:8000/ 2>/dev/null || echo "")
echo "${PAGE}" | grep -q 'setInterval\|POLL_INTERVAL' \
    && ok "Auto-refresh template confirmed (setInterval present)" || fail "Old template still serving — needs --no-cache rebuild"
echo "${PAGE}" | grep -q '0.2.1\|0.3.0' \
    && ok "Template version tag found" || warn "No version tag in template"

CRON_AQI=$(crontab -l 2>/dev/null | grep 'aqi_monitor.func' | grep -v '^#' || true)
[[ -n "${CRON_AQI}" ]] && ok "Crontab @reboot entry: ${CRON_AQI}" || fail "Crontab @reboot for aqi_monitor missing"

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
echo
echo "══════════════════════════════════════════════════════════════"
printf "  Validation: \033[0;32m%d passed\033[0m  \033[0;31m%d failed\033[0m\n" "${PASS}" "${FAIL}"
echo "══════════════════════════════════════════════════════════════"

if [[ "${FAIL}" -gt 0 ]]; then
    echo "  Fix failures above before promoting to main."
    echo "  Re-run: bash validate_and_promote.sh"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# PART 2 — WRITE install.sh
# ═══════════════════════════════════════════════════════════════
hdr "Writing install.sh v1.0.0"

cat > "${REPO}/install.sh" << 'INSTALLEOF'
#!/usr/bin/env bash
# =============================================================================
# install.sh v1.0.0
# Fresh deployment installer for pi_air_quality_monitor
# Tested on Raspberry Pi OS Bookworm (Debian 12)
# Usage: bash install.sh
# =============================================================================

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "  [\033[0;32mOK\033[0m] $*"; }

log "pi_air_quality_monitor installer v1.0.0"

# ── System dependencies ───────────────────────────────────────
log "Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y python3 python3-pip python3-dev libffi-dev libssl-dev jq curl nmap

# ── Docker ────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "${USER}"
    sudo systemctl enable docker
    ok "Docker installed — you may need to log out and back in for group membership"
else
    ok "Docker already installed: $(docker --version)"
fi

# ── docker-compose (v1 legacy — used by existing scripts) ────
if ! command -v docker-compose &>/dev/null; then
    log "Installing docker-compose..."
    sudo pip3 install docker-compose --break-system-packages 2>/dev/null \
        || sudo pip3 install docker-compose
fi
ok "docker-compose: $(docker-compose --version)"

# ── udev rule for SDS011 sensor ───────────────────────────────
log "Configuring udev rule for CH340 USB sensor..."
UDEV_RULE='SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", SYMLINK+="myUSB"'
UDEV_FILE="/etc/udev/rules.d/99_usbdevices.rules"
if ! grep -q "${UDEV_RULE}" "${UDEV_FILE}" 2>/dev/null; then
    echo "${UDEV_RULE}" | sudo tee "${UDEV_FILE}" > /dev/null
    sudo udevadm control --reload-rules
    ok "udev rule written: ${UDEV_FILE}"
else
    ok "udev rule already present"
fi

# ── Backward-compat symlink ───────────────────────────────────
FUNC_SRC="${REPO_DIR}/scripts/service/aqi_monitor.func"
FUNC_LINK="${REPO_DIR}/aqi_monitor.func"
if [[ ! -L "${FUNC_LINK}" ]]; then
    ln -s "${FUNC_SRC}" "${FUNC_LINK}"
    ok "Symlink created: aqi_monitor.func -> scripts/service/"
else
    ok "Symlink already exists"
fi

# ── .bashrc source ────────────────────────────────────────────
BASHRC="${HOME}/.bashrc"
BASHRC_LINE="source ${FUNC_SRC}"
if ! grep -q 'aqi_monitor.func' "${BASHRC}"; then
    cat >> "${BASHRC}" << BRCEOF

if [ -f ${FUNC_SRC} ] ; then
    source ${FUNC_SRC}
fi
BRCEOF
    ok ".bashrc updated"
else
    ok ".bashrc already sources aqi_monitor.func"
fi

# ── Crontab ───────────────────────────────────────────────────
log "Configuring crontab..."
CURRENT_CRON=$(crontab -l 2>/dev/null || true)
CRON_ENTRY="@reboot ${FUNC_SRC} start 2>/dev/null"
if ! echo "${CURRENT_CRON}" | grep -q 'aqi_monitor.func'; then
    (echo "${CURRENT_CRON}"; echo "${CRON_ENTRY}") | crontab -
    ok "Crontab @reboot entry added"
else
    ok "Crontab entry already present"
fi

# ── Build docker image ────────────────────────────────────────
log "Building Docker image..."
cd "${REPO_DIR}"
docker-compose build
ok "Image built: pi-air-quality-monitor"

# ── Redis sysctl fix ─────────────────────────────────────────
if ! grep -q 'vm.overcommit_memory' /etc/sysctl.conf 2>/dev/null; then
    echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf > /dev/null
    sudo sysctl vm.overcommit_memory=1 2>/dev/null || true
    ok "Redis: vm.overcommit_memory set"
fi

# ── Start service ─────────────────────────────────────────────
log "Starting service..."
source "${FUNC_SRC}"
aqi_monitor start
sleep 10
aqi_monitor status

echo
echo "══════════════════════════════════════════════════════════════"
echo "  Install complete — v1.0.0"
echo "  Web UI : http://$(hostname -I | awk '{print $1}'):8000"
echo "  API    : http://$(hostname -I | awk '{print $1}'):8000/api/"
echo "  Logs   : tail -f /tmp/sensor_logs/aqi_monitor.log"
echo "  Manage : aqi_monitor [start|stop|restart|status|api|log]"
echo "══════════════════════════════════════════════════════════════"
INSTALLEOF

chmod +x "${REPO}/install.sh"
ok "install.sh written"

# ═══════════════════════════════════════════════════════════════
# PART 3 — UPDATE VERSION AND CHANGELOG
# ═══════════════════════════════════════════════════════════════
hdr "Updating VERSION → 1.0.0"

echo "1.0.0" > "${REPO}/VERSION"

# Prepend release entry to CHANGELOG
TMPLOG=$(mktemp)
cat > "${TMPLOG}" << CLEOF
# Changelog

## [1.0.0] - $(date +%Y-%m-%d)
### Fixed
- sensor_online(): direct /dev/ttyUSBx check instead of dmesg-only
- aqi_monitor.func log redirect (double > redirect silenced all output)
- Path migration: custom/ → scripts/{kiosk,data,service}/
- Crontab and .bashrc updated to new script paths
- Backward-compat symlink at repo root for aqi_monitor.func

### Added
- Auto-refresh chart (60s polling, no page reload) — index.html v0.2.1
- Dark theme UI with live status indicator
- install.sh for fresh deployments
- VERSION and CHANGELOG.md with semantic versioning
- docs/diagnostics/ for deployment logs

### Architecture
- Flask + Redis + docker-compose stack unchanged
- SDS011 sensor via /dev/ttyUSB0 → docker device passthrough
- API: /api/ (historical), /api/now/ (live), /  (chart UI)
- Grafana compatible via HTTP data source at :8000/api/

CLEOF
grep -v '^# Changelog' "${REPO}/CHANGELOG.md" >> "${TMPLOG}" || true
mv "${TMPLOG}" "${REPO}/CHANGELOG.md"
ok "CHANGELOG.md updated"

# ═══════════════════════════════════════════════════════════════
# PART 4 — PROMOTE TO MAIN
# ═══════════════════════════════════════════════════════════════
hdr "Promoting custom_dev → main"

git add -A
git commit -m "release(v1.0.0): validated stable deployment

- All validation checks pass
- install.sh for fresh Pi deployments
- VERSION 1.0.0, CHANGELOG updated
- Auto-refresh UI, sensor detection fix, path migration complete" \
    2>/dev/null || log "Nothing new to commit"

log "Pushing custom_dev..."
git push origin custom_dev

log "Merging to main..."
git checkout main
git merge --no-ff custom_dev -m "release(v1.0.0): merge custom_dev — stable deployment

Validated deployment with:
- Auto-refresh chart (60s polling)
- Reliable sensor detection
- Correct script paths and crontab
- install.sh for fresh deployments"

git tag -a v1.0.0 -m "v1.0.0 — stable Pi AQI monitor deployment"
git push origin main
git push origin v1.0.0

git checkout custom_dev

echo
echo "══════════════════════════════════════════════════════════════"
echo "  Released v1.0.0"
echo "  Branch custom_dev merged → main"
echo "  Tag: v1.0.0"
echo "  github.com/codeddarkness/pi_air_quality_monitor"
echo
echo "  Service status:"
aqi_monitor status
echo
echo "  Web UI : http://$(hostname -I | awk '{print $1}'):8000"
echo "  API    : http://$(hostname -I | awk '{print $1}'):8000/api/"
echo "══════════════════════════════════════════════════════════════"
