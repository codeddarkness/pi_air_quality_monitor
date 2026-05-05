#!/usr/bin/env bash
# =============================================================================
# setup_v1.1.0.sh
# - Creates v1.1.0-dev branch from custom_dev
# - Adds upstream attribution (NOTICE + README update)
# - Installs systemd units for paqm (docker stack) and firefox kiosk
# - Disables @reboot crontab entries (replaced by systemd)
# - Validates autostart order
# =============================================================================

set -euo pipefail
REPO="${HOME}/pi_air_quality_monitor"
cd "${REPO}"

log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "  [\033[0;32mOK\033[0m] $*"; }
warn(){ echo -e "  [\033[0;33mWARN\033[0m] $*"; }

# ── 0. Branch setup ───────────────────────────────────────────────────────────
log "Creating v1.1.0-dev branch from custom_dev..."
git checkout custom_dev
git pull origin custom_dev 2>/dev/null || true
git checkout -b v1.1.0-dev 2>/dev/null || git checkout v1.1.0-dev
echo "1.1.0-dev" > VERSION
ok "Branch: v1.1.0-dev"

# ── 1. Upstream attribution ───────────────────────────────────────────────────
log "Writing NOTICE file (upstream attribution)..."
cat > NOTICE << 'EOF'
pi_air_quality_monitor
Copyright (c) codeddarkness
https://github.com/codeddarkness/pi_air_quality_monitor

This project is a fork/mirror of:

  pi_air_quality_monitor
  Copyright (c) rydercalmdown
  https://github.com/rydercalmdown/pi_air_quality_monitor

The original project provided the core Flask + Redis + Docker architecture,
SDS011 sensor integration, Chart.js web interface, and APScheduler data
collection loop. This fork adds:

  - Auto-refresh chart UI (60s polling, dark theme)
  - Reliable sensor detection (/dev/ttyUSBx direct check)
  - Systemd service units for autostart (paqm + firefox kiosk)
  - Structured script layout (scripts/kiosk, scripts/data, scripts/service)
  - install.sh for reproducible fresh deployments
  - Versioning, CHANGELOG, and validation tooling

Original license applies to all upstream code. See LICENSE if present in
the upstream repository.
EOF
ok "NOTICE written"

# Update README with upstream credit section
python3 - << 'PYEOF'
path = "/home/pi/pi_air_quality_monitor/README.md"
with open(path) as f:
    content = f.read()

credit = """
## Upstream / Credits

This project is a fork of [rydercalmdown/pi_air_quality_monitor](https://github.com/rydercalmdown/pi_air_quality_monitor).

The original work provides the Flask + Redis + Docker stack, SDS011 sensor
integration via `sds011lib`, Chart.js web interface, and APScheduler-based
data collection. All upstream code retains its original authorship.

**Changes in this fork** are documented in [CHANGELOG.md](CHANGELOG.md)
and [NOTICE](NOTICE).

---
"""

marker = "## Known Issues"
if "## Upstream" not in content:
    content = content.replace(marker, credit + marker)
    with open(path, "w") as f:
        f.write(content)
    print("OK: upstream credit added to README")
else:
    print("OK: upstream credit already present")
PYEOF

# ── 2. Write paqm.service systemd unit ───────────────────────────────────────
log "Writing systemd/paqm.service..."
cat > systemd/paqm.service << 'EOF'
# paqm.service v1.1.0
# Pi Air Quality Monitor — starts docker-compose stack at boot
# After docker.service ensures daemon is ready before compose runs
[Unit]
Description=Pi Air Quality Monitor (docker-compose stack)
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
User=pi
Group=docker
WorkingDirectory=/home/pi/pi_air_quality_monitor
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/docker-compose up
ExecStop=/usr/bin/docker-compose down
Restart=on-failure
RestartSec=15
StandardOutput=append:/tmp/sensor_logs/paqm-systemd.log
StandardError=append:/tmp/sensor_logs/paqm-systemd.log

[Install]
WantedBy=multi-user.target
EOF
ok "systemd/paqm.service written"

# ── 3. Write firefox-kiosk.service systemd unit ───────────────────────────────
log "Writing systemd/firefox-kiosk.service..."
cat > systemd/firefox-kiosk.service << 'EOF'
# firefox-kiosk.service v1.1.0
# Opens Firefox ESR in kiosk mode after paqm stack is healthy
[Unit]
Description=Firefox Kiosk — AQI Monitor display
After=graphical.target paqm.service
Wants=graphical.target
BindsTo=paqm.service

[Service]
User=pi
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority
WorkingDirectory=/home/pi/pi_air_quality_monitor
# Wait for Flask to be ready before opening browser
ExecStartPre=/bin/bash -c '\
  for i in $(seq 1 30); do \
    curl -sf http://localhost:8000/api/ >/dev/null 2>&1 && exit 0; \
    echo "Waiting for AQI API... attempt $i"; \
    sleep 3; \
  done; \
  echo "WARNING: API not ready after 90s, starting anyway"; exit 0'
ExecStart=/home/pi/pi_air_quality_monitor/scripts/kiosk/start_firefox_kiosk.sh
ExecStop=/bin/bash -c "pkill -f start_firefox_kiosk.sh; killall firefox-esr 2>/dev/null; true"
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=10
Restart=on-failure
RestartSec=10
StandardOutput=append:/home/pi/pi_air_quality_monitor/logs/firefox-kiosk-systemd.log
StandardError=append:/home/pi/pi_air_quality_monitor/logs/firefox-kiosk-systemd.log

[Install]
WantedBy=graphical.target
EOF
ok "systemd/firefox-kiosk.service written"

# ── 4. Install systemd units ──────────────────────────────────────────────────
log "Installing systemd units..."
mkdir -p /tmp/sensor_logs
mkdir -p "${REPO}/logs"

sudo cp systemd/paqm.service /etc/systemd/system/paqm.service
sudo cp systemd/firefox-kiosk.service /etc/systemd/system/firefox-kiosk.service
sudo chmod 644 /etc/systemd/system/paqm.service
sudo chmod 644 /etc/systemd/system/firefox-kiosk.service
sudo systemctl daemon-reload
ok "Unit files installed and daemon reloaded"

# Enable both services
sudo systemctl enable paqm.service
ok "paqm.service enabled"
sudo systemctl enable firefox-kiosk.service
ok "firefox-kiosk.service enabled"

# ── 5. Disable @reboot crontab entries (replaced by systemd) ─────────────────
log "Commenting out @reboot crontab entries (replaced by systemd)..."
CURRENT_CRON=$(crontab -l 2>/dev/null || true)
NEW_CRON=$(echo "${CURRENT_CRON}" | sed \
    's|^@reboot.*aqi_monitor.func.*|# DISABLED - replaced by paqm.service systemd unit\n# &|g')
echo "${NEW_CRON}" | crontab -
ok "Crontab @reboot entries disabled"

# ── 6. Update CHANGELOG ───────────────────────────────────────────────────────
log "Updating CHANGELOG..."
TMPLOG=$(mktemp)
cat > "${TMPLOG}" << CLEOF
# Changelog

## [1.1.0-dev] - $(date +%Y-%m-%d)
### Added
- NOTICE file with upstream attribution to rydercalmdown/pi_air_quality_monitor
- README: upstream credit section with link to original project
- systemd/paqm.service: docker-compose stack with After=docker.service
- systemd/firefox-kiosk.service: kiosk After=paqm.service with API health check
- ExecStartPre health check loop: waits up to 90s for Flask API before opening browser

### Fixed
- Boot autostart: replaced racy @reboot crontab with ordered systemd units
  (crontab fires before Docker daemon ready; systemd Requires= prevents this)
- firefox-kiosk: was opening localhost:8000 before Flask was serving requests

### Changed
- @reboot crontab entries commented out (paqm.service takes over)

CLEOF
grep -v '^# Changelog' "${REPO}/CHANGELOG.md" >> "${TMPLOG}" || true
mv "${TMPLOG}" "${REPO}/CHANGELOG.md"
ok "CHANGELOG updated"

# ── 7. Start services now (without rebooting) ─────────────────────────────────
log "Starting paqm.service..."
sudo systemctl start paqm.service
sleep 15

log "Checking paqm status..."
if sudo systemctl is-active --quiet paqm.service; then
    ok "paqm.service is active"
    docker ps | grep -E 'pi-air|redis' && ok "Containers confirmed running" || warn "Containers not visible yet"
else
    warn "paqm.service not active — check: sudo journalctl -u paqm.service -n 30"
fi

log "Starting firefox-kiosk.service..."
sudo systemctl start firefox-kiosk.service &
ok "firefox-kiosk.service started (health check running in background)"

# ── 8. Commit and push ────────────────────────────────────────────────────────
log "Committing v1.1.0-dev..."
git add -A
git commit -m "feat(v1.1.0-dev): systemd autostart + upstream attribution

- NOTICE: credit to rydercalmdown/pi_air_quality_monitor (upstream)
- README: upstream credit section
- systemd/paqm.service: proper After=docker.service boot ordering
- systemd/firefox-kiosk.service: waits for API health before opening browser
- @reboot crontab entries disabled (systemd takes over)
- VERSION: 1.1.0-dev"

git push -u origin v1.1.0-dev
ok "Branch v1.1.0-dev pushed"

# ── 9. Print upstream notification template ───────────────────────────────────
echo
echo "══════════════════════════════════════════════════════════════"
echo "  v1.1.0-dev deployed"
echo
echo "  Services:"
sudo systemctl status paqm.service --no-pager -l | grep -E 'Active:|Main PID' || true
echo
echo "  Logs:"
echo "    sudo journalctl -u paqm.service -f"
echo "    sudo journalctl -u firefox-kiosk.service -f"
echo
echo "══════════════════════════════════════════════════════════════"
echo "  UPSTREAM NOTIFICATION"
echo "  Open this issue at: https://github.com/rydercalmdown/pi_air_quality_monitor/issues/new"
echo "──────────────────────────────────────────────────────────────"
cat << 'ISSUE'
Title: Fork notification — codeddarkness/pi_air_quality_monitor

Hi! I wanted to let you know I've forked your project and wanted to share
what I've built on top of it in case any of it is useful upstream.

Fork: https://github.com/codeddarkness/pi_air_quality_monitor

Changes made:
- Auto-refreshing chart UI (60s polling via setInterval, no page reload)
- Dark theme web interface
- More robust sensor detection (checks /dev/ttyUSBx directly vs dmesg-only)
- Systemd service units for reliable boot autostart (paqm + Firefox kiosk)
- install.sh for reproducible fresh deployments on Pi OS Bookworm
- Scripts reorganized into scripts/{service,data,kiosk}/
- CHANGELOG, VERSION, and validation tooling

Happy to open a PR for any of these if they'd be useful to the upstream project.
Thanks for the great starting point!
ISSUE
echo "══════════════════════════════════════════════════════════════"
