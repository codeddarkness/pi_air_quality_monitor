#!/usr/bin/env bash
# =============================================================================
# setup_v1.2.0.sh
# - Creates v1.2.0-dev branch
# - Removes hardcoded IPs, usernames, hostnames → config.env system
# - Migrates docker-compose v1 → docker compose V2
# - Adds /metrics Prometheus endpoint to Flask
# - Fixes Redis persistence (named volume + appendonly)
# - Updates all scripts, systemd units, Makefile to use config vars
# =============================================================================

set -euo pipefail
REPO="${HOME}/pi_air_quality_monitor"
cd "${REPO}"

log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "  [\033[0;32mOK\033[0m] $*"; }

REAL_DIR=$(realpath "${REPO}")
REAL_USER=$(whoami)

# ── 0. Branch ─────────────────────────────────────────────────────────────────
log "Creating v1.2.0-dev from main..."
git checkout main && git pull origin main
git checkout -b v1.2.0-dev 2>/dev/null || git checkout v1.2.0-dev
echo "1.2.0-dev" > VERSION
ok "Branch: v1.2.0-dev"

# ── 1. config.env system ──────────────────────────────────────────────────────
log "Creating config.env.example..."
cat > config.env.example << 'EOF'
# =============================================================================
# pi_air_quality_monitor — deployment configuration
# Copy this file to config.env and edit for your system.
# config.env is gitignored — never committed.
# =============================================================================

# User that runs the service (must be in docker group)
PAQM_USER=pi

# Absolute path to the repo on this system
PAQM_DIR=${PAQM_DIR}

# Web interface port
PAQM_PORT=8000

# Docker compose project name (avoids naming conflicts on shared hosts)
COMPOSE_PROJECT_NAME=pi_air_quality_monitor

# Display for kiosk mode
KIOSK_DISPLAY=:0

# URL the kiosk browser opens (defaults to localhost:PAQM_PORT)
KIOSK_URL=http://localhost:8000
EOF

# Write config.env for this system if absent
if [[ ! -f config.env ]]; then
    sed -e "s|PAQM_USER=pi|PAQM_USER=${REAL_USER}|g" \
        -e "s|PAQM_DIR=${PAQM_DIR}|PAQM_DIR=${REAL_DIR}|g" \
        -e "s|KIOSK_URL=http://localhost:8000|KIOSK_URL=http://localhost:8000|g" \
        config.env.example > config.env
    ok "config.env written (user=${REAL_USER}, dir=${REAL_DIR})"
else
    ok "config.env exists — not overwritten"
fi

grep -q '^config\.env$' .gitignore || echo 'config.env' >> .gitignore
ok "config.env gitignored"

# ── 2. Scrub PII from all tracked files ──────────────────────────────────────
log "Scrubbing IPs, hostnames, hardcoded paths from tracked files..."
python3 - << PYEOF
import os, re, glob

repo = "${REAL_DIR}"
real_user = "${REAL_USER}"

subs = [
    (r'10\.0\.0\.194', '<PI_IP_ADDRESS>'),
    (r'10\.0\.0\.172', '<PI_IP_ADDRESS>'),
    (r'<PI_HOSTNAME>\.<DOMAIN>', '<PI_HOSTNAME>'),
    (r'\baqipimon\b', '<PI_HOSTNAME>'),
    (r'\bdarkremy\b', '<DOMAIN>'),
    (r'PI_IP_ADDRESS=10\.\d+\.\d+\.\d+', 'PI_IP_ADDRESS=<PI_IP_ADDRESS>'),
    (r'${PAQM_DIR}', '\${PAQM_DIR}'),
    (r'PI_USERNAME=${PAQM_USER}\b', 'PI_USERNAME=\${PAQM_USER}'),
]

skip = ['.git/', 'config.env', 'data/', 'logs/', '__pycache__', '.pyc']
exts = ['*.md','*.sh','*.yaml','*.yml','*.service','*.func','Makefile',
        'NOTICE','install.sh','CHANGELOG.md']

files = []
for pat in exts:
    files += glob.glob(os.path.join(repo,'**',pat), recursive=True)
files = [f for f in files if not any(s in f for s in skip)]

changed = []
for fpath in files:
    try:
        orig = open(fpath).read()
    except Exception:
        continue
    new = orig
    for pat, rep in subs:
        new = re.sub(pat, rep, new)
    if new != orig:
        open(fpath,'w').write(new)
        changed.append(os.path.relpath(fpath, repo))

[print(f"  scrubbed: {f}") for f in changed]
print(f"OK: {len(changed)} files updated")
PYEOF

# ── 3. Makefile (V2 + config.env) ────────────────────────────────────────────
log "Rewriting Makefile..."
cat > Makefile << 'MAKEEOF'
# pi_air_quality_monitor Makefile v1.2.0
# Copy config.env.example → config.env and edit before deploying.

-include config.env
export

PAQM_USER            ?= pi
PAQM_DIR             ?= $(shell pwd)
PAQM_PORT            ?= 8000
COMPOSE_PROJECT_NAME ?= pi_air_quality_monitor

.PHONY: run stop restart status build install validate copy shell log api metrics

run:
	@source scripts/service/aqi_monitor.func && aqi_monitor start

stop:
	@source scripts/service/aqi_monitor.func && aqi_monitor stop

restart:
	@source scripts/service/aqi_monitor.func && aqi_monitor restart

status:
	@source scripts/service/aqi_monitor.func && aqi_monitor status

build:
	@docker compose build

install:
	@bash install.sh

validate:
	@bash -c '\
	  echo "=== Sensor ==="; ls /dev/ttyUSB* 2>/dev/null || echo "  not found"; \
	  echo "=== Containers ==="; \
	  docker ps --filter name=$(COMPOSE_PROJECT_NAME) \
	    --format "  {{.Names}} — {{.Status}}"; \
	  echo "=== API ==="; \
	  curl -sf http://localhost:$(PAQM_PORT)/api/ | python3 -c \
	    "import json,sys; d=json.load(sys.stdin); \
	     print(\"  readings:\",len(d[\"historical\"][\"labels\"]), \
	           \"| AQI:\",d[\"historical\"][\"aqi\"][\"data\"][-1])" \
	    2>/dev/null || echo "  not responding"; \
	  echo "=== Metrics ==="; \
	  curl -sf http://localhost:$(PAQM_PORT)/metrics | grep -E "^aqi|^pm" || \
	    echo "  not responding"'

copy:
	@test -n "$(TARGET_HOST)" || (echo "Usage: make copy TARGET_HOST=user@host"; exit 1)
	rsync -av $(PAQM_DIR)/ --exclude .git --exclude data/redis --exclude logs \
	  --exclude _local_data --exclude '*.pyc' --exclude config.env \
	  $(TARGET_HOST):$(PAQM_DIR)/

shell:
	@test -n "$(TARGET_HOST)" || (echo "Usage: make shell TARGET_HOST=user@host"; exit 1)
	ssh $(TARGET_HOST)

log:
	@tail -f /tmp/sensor_logs/aqi_monitor.log

api:
	@curl -s http://localhost:$(PAQM_PORT)/api/ | python3 -m json.tool

metrics:
	@curl -s http://localhost:$(PAQM_PORT)/metrics
MAKEEOF
ok "Makefile written"

# ── 4. docker-compose.yaml (V2 + named volume) ───────────────────────────────
log "Updating docker-compose.yaml..."
cat > docker-compose.yaml << 'DCEOF'
# docker-compose.yaml v1.2.0
# docker compose V2 syntax — no 'version' key needed

services:
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --save 60 1 --save 300 10 --appendonly yes
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

  web:
    build: .
    image: pi-air-quality-monitor
    restart: unless-stopped
    devices:
      - "/dev/ttyUSB0:/dev/ttyUSB0"
    environment:
      - REDIS_HOST=redis
      - PORT=${PAQM_PORT:-8000}
    volumes:
      - ./src:/code
    depends_on:
      redis:
        condition: service_healthy
    ports:
      - "${PAQM_PORT:-8000}:${PAQM_PORT:-8000}"

volumes:
  redis_data:
    driver: local
DCEOF
ok "docker-compose.yaml updated (V2, named volume, Redis persistence)"

# ── 5. /metrics endpoint ──────────────────────────────────────────────────────
log "Adding /metrics to src/app.py..."
cat > src/app.py << 'PYEOF'
# app.py v1.2.0
import os
import time
from flask import Flask, jsonify, render_template, Response
from AirQualityMonitor import AirQualityMonitor
from apscheduler.schedulers.background import BackgroundScheduler
import atexit
from flask_cors import CORS, cross_origin

app = Flask(__name__)
CORS(app)
app.config['CORS_HEADERS'] = 'Content-Type'
aqm = AirQualityMonitor()

scheduler = BackgroundScheduler()
scheduler.add_job(func=aqm.save_measurement_to_redis, trigger="interval", seconds=60)
scheduler.start()
atexit.register(lambda: scheduler.shutdown())


def pretty_timestamps(measurement):
    return [x['measurement']['timestamp'].split('.')[0] for x in measurement]


def reconfigure_data(measurement):
    measurement = list(reversed(measurement[:30]))
    return {
        'labels': pretty_timestamps(measurement),
        'aqi':  {'label':'aqi',   'data':[x['measurement']['aqi']     for x in measurement],
                 'backgroundColor':'#181d27','borderColor':'#181d27','borderWidth':3},
        'pm10': {'label':'pm10',  'data':[x['measurement']['pm10']    for x in measurement],
                 'backgroundColor':'#cc0000','borderColor':'#cc0000','borderWidth':3},
        'pm2':  {'label':'pm2.5', 'data':[x['measurement']['pm2.5']  for x in measurement],
                 'backgroundColor':'#42C0FB','borderColor':'#42C0FB','borderWidth':3},
    }


@app.route('/')
def index():
    return render_template('index.html',
        context={'historical': reconfigure_data(aqm.get_last_n_measurements())})


@app.route('/api/')
@cross_origin()
def api():
    return jsonify({'historical': reconfigure_data(aqm.get_last_n_measurements())})


@app.route('/api/now/')
def api_now():
    return jsonify({'current': aqm.get_measurement()})


@app.route('/metrics')
def metrics():
    """Prometheus text format — use as Grafana HTTP data source or Prometheus scrape target."""
    try:
        data = aqm.get_last_n_measurements()
        if not data:
            return Response('# No data yet\n', mimetype='text/plain; version=0.0.4')
        latest = data[0]['measurement']
        ts_ms  = int(data[0]['time'] * 1000)
        out = (
            '# HELP aqi_index Air Quality Index (EPA)\n'
            '# TYPE aqi_index gauge\n'
            f'aqi_index {latest["aqi"]} {ts_ms}\n'
            '# HELP pm10_ugm3 PM10 particulate matter ug/m3\n'
            '# TYPE pm10_ugm3 gauge\n'
            f'pm10_ugm3 {latest["pm10"]} {ts_ms}\n'
            '# HELP pm25_ugm3 PM2.5 particulate matter ug/m3\n'
            '# TYPE pm25_ugm3 gauge\n'
            f'pm25_ugm3 {latest["pm2.5"]} {ts_ms}\n'
            '# HELP aqi_readings_total Total readings in Redis\n'
            '# TYPE aqi_readings_total counter\n'
            f'aqi_readings_total {len(data)}\n'
        )
        return Response(out, mimetype='text/plain; version=0.0.4')
    except Exception as e:
        return Response(f'# Error: {e}\n', mimetype='text/plain; version=0.0.4', status=500)


if __name__ == "__main__":
    app.run(debug=True, use_reloader=False, host='0.0.0.0',
            port=int(os.environ.get('PORT', '8000')))
PYEOF
ok "src/app.py updated with /metrics"

# ── 6. Systemd units ──────────────────────────────────────────────────────────
log "Updating systemd units..."
cat > systemd/paqm.service << SVCEOF
# paqm.service v1.2.0
[Unit]
Description=Pi Air Quality Monitor (docker compose stack)
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
User=${REAL_USER}
Group=docker
WorkingDirectory=${REAL_DIR}
EnvironmentFile=-${REAL_DIR}/config.env
Environment=COMPOSE_PROJECT_NAME=pi_air_quality_monitor
ExecStartPre=/bin/mkdir -p /tmp/sensor_logs
ExecStartPre=/usr/bin/docker compose -p pi_air_quality_monitor down --remove-orphans
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/docker compose -p pi_air_quality_monitor up
ExecStop=/usr/bin/docker compose -p pi_air_quality_monitor down
Restart=on-failure
RestartSec=15
StandardOutput=append:/tmp/sensor_logs/paqm-systemd.log
StandardError=append:/tmp/sensor_logs/paqm-systemd.log

[Install]
WantedBy=multi-user.target
SVCEOF

cat > systemd/firefox-kiosk.service << SVCEOF
# firefox-kiosk.service v1.2.0
[Unit]
Description=Firefox Kiosk — AQI Monitor display
After=graphical.target paqm.service
Wants=graphical.target paqm.service

[Service]
User=${REAL_USER}
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/${REAL_USER}/.Xauthority
EnvironmentFile=-${REAL_DIR}/config.env
WorkingDirectory=${REAL_DIR}
ExecStart=${REAL_DIR}/scripts/kiosk/kiosk_foreground.sh
ExecStop=/bin/bash -c "killall firefox-esr 2>/dev/null; true"
Restart=on-failure
RestartSec=15
StandardOutput=append:${REAL_DIR}/logs/firefox-kiosk-systemd.log
StandardError=append:${REAL_DIR}/logs/firefox-kiosk-systemd.log

[Install]
WantedBy=graphical.target
SVCEOF
ok "Systemd units updated"

# ── 7. Update kiosk script ────────────────────────────────────────────────────
cat > scripts/kiosk/kiosk_foreground.sh << 'KEOF'
#!/usr/bin/env bash
# kiosk_foreground.sh v1.2.0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"
[[ -f "${REPO_DIR}/config.env" ]] && source "${REPO_DIR}/config.env"

DISPLAY="${KIOSK_DISPLAY:-:0}"
URL="${KIOSK_URL:-http://localhost:${PAQM_PORT:-8000}}"
LOG="${REPO_DIR}/logs/firefox-kiosk.log"
export DISPLAY
export XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
mkdir -p "$(dirname "${LOG}")"
ts() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*" | tee -a "${LOG}"; }

ts "Kiosk v1.2.0 — waiting for ${URL}/api/"
for i in $(seq 1 40); do
    curl -sf "${URL}/api/" >/dev/null 2>&1 && { ts "API ready (${i})"; break; }
    ts "Waiting ${i}/40"; sleep 5
done
ts "exec firefox-esr --kiosk ${URL}"
exec firefox-esr --kiosk "${URL}" 2>>"${LOG}"
KEOF
chmod +x scripts/kiosk/kiosk_foreground.sh
ok "kiosk_foreground.sh updated"

# ── 8. Update aqi_monitor.func: docker-compose → docker compose ──────────────
log "Updating aqi_monitor.func to docker compose V2..."
sed -i 's/docker-compose /docker compose /g' scripts/service/aqi_monitor.func
ok "aqi_monitor.func: docker-compose → docker compose"

# ── 9. Update install.sh ──────────────────────────────────────────────────────
log "Updating install.sh..."
cat > install.sh << 'IEOF'
#!/usr/bin/env bash
# install.sh v1.2.0
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_USER="$(whoami)"
log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "  [\033[0;32mOK\033[0m] $*"; }

log "pi_air_quality_monitor installer v1.2.0"

# Generate config.env if absent
if [[ ! -f "${REPO_DIR}/config.env" ]]; then
    sed -e "s|PAQM_USER=pi|PAQM_USER=${REAL_USER}|g" \
        -e "s|PAQM_DIR=${PAQM_DIR}|PAQM_DIR=${REPO_DIR}|g" \
        "${REPO_DIR}/config.env.example" > "${REPO_DIR}/config.env"
    ok "config.env generated"
fi
source "${REPO_DIR}/config.env"

log "Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y python3 python3-pip python3-dev libffi-dev libssl-dev jq curl

# Docker
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "${REAL_USER}"
    sudo systemctl enable docker
    ok "Docker installed"
else
    ok "Docker: $(docker --version)"
fi

# docker compose V2
if docker compose version &>/dev/null 2>&1; then
    ok "docker compose V2: $(docker compose version)"
else
    log "Installing docker compose V2 plugin..."
    sudo apt-get install -y docker-compose-plugin 2>/dev/null || true
    docker compose version &>/dev/null && ok "docker compose V2 installed" || \
        echo "  WARNING: could not install docker compose V2"
fi

# udev rule for SDS011
UDEV_RULE='SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", SYMLINK+="myUSB"'
UDEV_FILE="/etc/udev/rules.d/99_usbdevices.rules"
grep -q "${UDEV_RULE}" "${UDEV_FILE}" 2>/dev/null || {
    echo "${UDEV_RULE}" | sudo tee "${UDEV_FILE}" > /dev/null
    sudo udevadm control --reload-rules
    ok "udev rule written"
}

# Symlink + .bashrc
FUNC_SRC="${REPO_DIR}/scripts/service/aqi_monitor.func"
[[ -L "${REPO_DIR}/aqi_monitor.func" ]] || ln -s "${FUNC_SRC}" "${REPO_DIR}/aqi_monitor.func"
grep -q 'aqi_monitor.func' "${HOME}/.bashrc" || \
    echo "[ -f ${FUNC_SRC} ] && source ${FUNC_SRC}" >> "${HOME}/.bashrc"

# Redis sysctl
grep -q 'vm.overcommit_memory' /etc/sysctl.conf 2>/dev/null || {
    echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf > /dev/null
    sudo sysctl vm.overcommit_memory=1 2>/dev/null || true
}

# Build
log "Building Docker image..."
cd "${REPO_DIR}"
docker compose build
ok "Image built"

# Install systemd services
sudo cp "${REPO_DIR}/systemd/paqm.service" /etc/systemd/system/paqm.service
sudo cp "${REPO_DIR}/systemd/firefox-kiosk.service" /etc/systemd/system/firefox-kiosk.service
sudo sed -i "s|\${PAQM_DIR}|${REPO_DIR}|g; s|\${PAQM_USER}|${REAL_USER}|g; s|\${REAL_USER}|${REAL_USER}|g; s|\${REAL_DIR}|${REPO_DIR}|g" \
    /etc/systemd/system/paqm.service /etc/systemd/system/firefox-kiosk.service
sudo systemctl daemon-reload
sudo systemctl enable paqm.service firefox-kiosk.service
ok "Services enabled"

log "Starting paqm.service..."
sudo systemctl start paqm.service
sleep 15
source "${FUNC_SRC}"
aqi_monitor status

echo
echo "══════════════════════════════════════════════════════════════"
echo "  Install complete — v1.2.0"
echo "  Web     : http://$(hostname -I | awk '{print $1}'):${PAQM_PORT:-8000}"
echo "  API     : http://$(hostname -I | awk '{print $1}'):${PAQM_PORT:-8000}/api/"
echo "  Metrics : http://$(hostname -I | awk '{print $1}'):${PAQM_PORT:-8000}/metrics"
echo "  Config  : ${REPO_DIR}/config.env"
echo "══════════════════════════════════════════════════════════════"
IEOF
chmod +x install.sh
ok "install.sh updated"

# ── 10. Install + rebuild on this system ──────────────────────────────────────
log "Installing updated units on this system..."
sudo systemctl stop paqm.service 2>/dev/null || true
sudo cp systemd/paqm.service /etc/systemd/system/paqm.service
sudo cp systemd/firefox-kiosk.service /etc/systemd/system/firefox-kiosk.service
# Resolve shell vars in installed unit files for this system
sudo sed -i \
    -e "s|\${REAL_DIR}|${REAL_DIR}|g" \
    -e "s|\${REAL_USER}|${REAL_USER}|g" \
    /etc/systemd/system/paqm.service \
    /etc/systemd/system/firefox-kiosk.service
sudo systemctl daemon-reload
ok "Units installed"

log "Checking docker compose V2..."
if docker compose version &>/dev/null 2>&1; then
    ok "$(docker compose version)"
    DC_CMD="docker compose"
else
    warn "docker compose V2 not available — falling back to docker-compose"
    sudo apt-get install -y docker-compose-plugin 2>/dev/null || true
    DC_CMD="docker-compose"
fi

log "Rebuilding image..."
${DC_CMD} down 2>/dev/null || true
${DC_CMD} build

log "Starting paqm.service..."
sudo systemctl start paqm.service
sleep 20

log "Verifying..."
source scripts/service/aqi_monitor.func
aqi_monitor status

sleep 5
METRICS=$(curl -sf http://localhost:8000/metrics 2>/dev/null || echo "")
if echo "${METRICS}" | grep -q 'aqi_index'; then
    ok "/metrics endpoint live"
    echo "${METRICS}" | grep -E '^aqi|^pm'
else
    echo "  /metrics not ready yet (container may still be warming up)"
fi

# ── 11. Commit ────────────────────────────────────────────────────────────────
log "Committing v1.2.0-dev..."
git add -A
git commit -m "feat(v1.2.0-dev): config system, compose V2, metrics, no PII

- config.env.example: deployment template (committed)
  config.env: local overrides (gitignored, generated by install.sh)
- Scrubbed all IPs/hostnames/hardcoded paths from tracked files
- docker-compose.yaml: V2 syntax, named volume redis_data,
  Redis appendonly persistence, healthcheck on redis before web starts
- src/app.py: /metrics Prometheus endpoint
  (aqi_index, pm10_ugm3, pm25_ugm3, aqi_readings_total)
- aqi_monitor.func: docker-compose -> docker compose
- Makefile: config.env aware, TARGET_HOST for copy/shell
- install.sh: generates config.env, installs compose V2 plugin
- systemd units: EnvironmentFile=-config.env, compose V2"

git push -u origin v1.2.0-dev
ok "Branch v1.2.0-dev pushed"

echo
echo "══════════════════════════════════════════════════════════════"
echo "  v1.2.0-dev ready"
echo "  github.com/codeddarkness/pi_air_quality_monitor (v1.2.0-dev)"
echo
echo "  New endpoints:"
echo "    /metrics  — Prometheus scrape target"
echo "               curl http://$(hostname -I | awk '{print $1}'):8000/metrics"
echo
echo "  Grafana setup (Prometheus data source):"
echo "    URL: http://$(hostname -I | awk '{print $1}'):8000/metrics"
echo "    Metrics: aqi_index, pm10_ugm3, pm25_ugm3"
echo
echo "  To deploy on a new system:"
echo "    git clone git@github.com:codeddarkness/pi_air_quality_monitor.git"
echo "    cd pi_air_quality_monitor"
echo "    cp config.env.example config.env && \$EDITOR config.env"
echo "    bash install.sh"
echo "══════════════════════════════════════════════════════════════"
