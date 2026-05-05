#!/usr/bin/env bash
# =============================================================================
# patch_systemd_services.sh v1.1.1
# Fixes:
#   - paqm.service: /tmp/sensor_logs missing at start, docker-compose path
#   - firefox-kiosk.service: BindsTo too strict, script exits immediately
#     (backgrounded children confuse Type=simple)
#     Fix: use firefox-esr --kiosk directly, stays in foreground for systemd
# =============================================================================

set -euo pipefail
REPO="${HOME}/pi_air_quality_monitor"
cd "${REPO}"

log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "  [\033[0;32mOK\033[0m] $*"; }
warn(){ echo -e "  [\033[0;33mWARN\033[0m] $*"; }

# ── Detect docker-compose binary path ────────────────────────────────────────
DC=$(which docker-compose 2>/dev/null || echo "/usr/bin/docker-compose")
log "docker-compose binary: ${DC}"
[[ -x "${DC}" ]] && ok "docker-compose found: ${DC}" || { warn "docker-compose not at ${DC}"; DC=$(which docker-compose); }

# Check what failed in paqm last time
log "Last paqm journal entries:"
sudo journalctl -u paqm.service -n 20 --no-pager 2>/dev/null || true

# ── Stop both services before patching ───────────────────────────────────────
log "Stopping services..."
sudo systemctl stop paqm.service 2>/dev/null || true
sudo systemctl stop firefox-kiosk.service 2>/dev/null || true
sleep 2

# ── Fix paqm.service ──────────────────────────────────────────────────────────
log "Writing fixed paqm.service..."

# Ensure log dir exists NOW (also fixed in ExecStartPre)
mkdir -p /tmp/sensor_logs

cat > systemd/paqm.service << SVCEOF
# paqm.service v1.1.1
[Unit]
Description=Pi Air Quality Monitor (docker-compose stack)
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
User=pi
Group=docker
WorkingDirectory=${REPO}
# Create log dir before docker-compose tries to write
ExecStartPre=/bin/mkdir -p /tmp/sensor_logs
ExecStartPre=/bin/sleep 5
ExecStart=${DC} up
ExecStop=${DC} down
Restart=on-failure
RestartSec=15
StandardOutput=append:/tmp/sensor_logs/paqm-systemd.log
StandardError=append:/tmp/sensor_logs/paqm-systemd.log

[Install]
WantedBy=multi-user.target
SVCEOF
ok "paqm.service written (binary: ${DC})"

# ── Write kiosk wrapper that stays in foreground ──────────────────────────────
log "Writing kiosk-foreground wrapper..."
cat > scripts/kiosk/kiosk_foreground.sh << 'KEOF'
#!/usr/bin/env bash
# kiosk_foreground.sh v1.1.1
# Runs firefox-esr in kiosk mode, stays in foreground for systemd.
# Polls API before starting so we don't get a blank page.

DISPLAY="${DISPLAY:-:0}"
export DISPLAY
export XAUTHORITY="${XAUTHORITY:-/home/pi/.Xauthority}"
URL="http://localhost:8000"
LOG="/home/pi/pi_air_quality_monitor/logs/firefox-kiosk.log"

mkdir -p "$(dirname "${LOG}")"

ts() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*" | tee -a "${LOG}"; }

ts "Kiosk starting — waiting for API at ${URL}/api/"
for i in $(seq 1 40); do
    curl -sf "${URL}/api/" >/dev/null 2>&1 && { ts "API ready after ${i} attempts"; break; }
    ts "Attempt ${i}/40 — sleeping 5s"
    sleep 5
done

ts "Launching firefox-esr --kiosk ${URL}"
exec firefox-esr --kiosk "${URL}" 2>>"${LOG}"
KEOF
chmod +x scripts/kiosk/kiosk_foreground.sh
ok "kiosk_foreground.sh written"

# ── Fix firefox-kiosk.service ─────────────────────────────────────────────────
log "Writing fixed firefox-kiosk.service..."
cat > systemd/firefox-kiosk.service << SVCEOF
# firefox-kiosk.service v1.1.1
[Unit]
Description=Firefox Kiosk — AQI Monitor display
After=graphical.target paqm.service
Wants=graphical.target paqm.service

[Service]
User=pi
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority
WorkingDirectory=${REPO}
ExecStart=${REPO}/scripts/kiosk/kiosk_foreground.sh
ExecStop=/bin/bash -c "killall firefox-esr 2>/dev/null; true"
Restart=on-failure
RestartSec=15
StandardOutput=append:${REPO}/logs/firefox-kiosk-systemd.log
StandardError=append:${REPO}/logs/firefox-kiosk-systemd.log

[Install]
WantedBy=graphical.target
SVCEOF
ok "firefox-kiosk.service written (uses --kiosk flag, stays in foreground)"

# ── Install updated units ─────────────────────────────────────────────────────
log "Installing updated units..."
mkdir -p "${REPO}/logs"
sudo cp systemd/paqm.service /etc/systemd/system/paqm.service
sudo cp systemd/firefox-kiosk.service /etc/systemd/system/firefox-kiosk.service
sudo chmod 644 /etc/systemd/system/paqm.service /etc/systemd/system/firefox-kiosk.service
sudo systemctl daemon-reload
ok "Units installed, daemon reloaded"

# ── Start paqm and wait for containers ───────────────────────────────────────
log "Starting paqm.service..."
sudo systemctl start paqm.service
sleep 5

log "Waiting for AQI containers (up to 60s)..."
for i in $(seq 1 12); do
    WEB=$(docker ps --filter "name=pi_air_quality_monitor" --format "{{.Names}}" 2>/dev/null | grep web || true)
    if [[ -n "${WEB}" ]]; then
        ok "Web container up: ${WEB}"
        break
    fi
    echo "  ... attempt ${i}/12"
    sleep 5
done

log "paqm.service status:"
sudo systemctl status paqm.service --no-pager -l | grep -E 'Active:|Main PID|Error' || true

log "Waiting for Flask API..."
for i in $(seq 1 20); do
    curl -sf http://localhost:8000/api/ >/dev/null 2>&1 && { ok "API responding on port 8000"; break; }
    echo "  ... attempt ${i}/20"
    sleep 3
done

# ── Start kiosk ───────────────────────────────────────────────────────────────
log "Starting firefox-kiosk.service..."
sudo systemctl start firefox-kiosk.service
sleep 3
sudo systemctl status firefox-kiosk.service --no-pager -l | grep -E 'Active:|Main PID' || true

# ── Commit ────────────────────────────────────────────────────────────────────
log "Committing v1.1.1 fixes..."
git add -A
git commit -m "fix(v1.1.1): systemd service startup

paqm.service:
- ExecStartPre: mkdir /tmp/sensor_logs before docker-compose writes there
- Hardcode docker-compose binary path (avoids PATH issues in systemd env)

firefox-kiosk.service:
- Replace BindsTo (too strict) with Wants (tolerant of paqm delays)
- Replace start_firefox_kiosk.sh (backgrounds+exits) with kiosk_foreground.sh
  which uses 'exec firefox-esr --kiosk' — stays in foreground for systemd
- kiosk_foreground.sh polls API up to 40x5s=200s before opening browser"

git push origin v1.1.0-dev
ok "Pushed to v1.1.0-dev"

# ── Final status ──────────────────────────────────────────────────────────────
echo
echo "══════════════════════════════════════════════════════════════"
echo "  v1.1.1 patch applied"
echo
echo "  paqm.service:          $(sudo systemctl is-active paqm.service 2>/dev/null)"
echo "  firefox-kiosk.service: $(sudo systemctl is-active firefox-kiosk.service 2>/dev/null)"
echo
docker ps --format "  {{.Names}} — {{.Status}}" | grep -E 'pi_air|redis' || echo "  AQI containers: not yet running"
echo
echo "  Logs:"
echo "    sudo journalctl -u paqm.service -f"
echo "    sudo journalctl -u firefox-kiosk.service -f"
echo "    tail -f ${REPO}/logs/firefox-kiosk.log"
echo "    tail -f /tmp/sensor_logs/paqm-systemd.log"
echo "══════════════════════════════════════════════════════════════"
