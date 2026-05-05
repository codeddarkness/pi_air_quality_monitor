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
