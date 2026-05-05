#!/usr/bin/env bash
cd ~/pi_air_quality_monitor

# Write the Makefile (ASCII only)
cat > Makefile << 'MAKEEOF'
# pi_air_quality_monitor Makefile v1.2.0
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
	@bash -c 'echo "=== Sensor ==="; ls /dev/ttyUSB* 2>/dev/null || echo "  not found"; echo "=== Containers ==="; docker ps --filter name=$(COMPOSE_PROJECT_NAME) --format "  {{.Names}} - {{.Status}}"; echo "=== API ==="; curl -sf http://localhost:$(PAQM_PORT)/api/ | python3 -c "import json,sys; d=json.load(sys.stdin); print(\"  readings:\",len(d[\"historical\"][\"labels\"]),\"| AQI:\",d[\"historical\"][\"aqi\"][\"data\"][-1])" 2>/dev/null || echo "  not responding"; echo "=== Metrics ==="; curl -sf http://localhost:$(PAQM_PORT)/metrics | grep -E "^aqi|^pm" || echo "  not responding"'
copy:
	@test -n "$(TARGET_HOST)" || (echo "Usage: make copy TARGET_HOST=user@host"; exit 1)
	rsync -av $(PAQM_DIR)/ --exclude .git --exclude data/redis --exclude logs --exclude _local_data --exclude '*.pyc' --exclude config.env $(TARGET_HOST):$(PAQM_DIR)/
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

# docker-compose V2 + named volume
cat > docker-compose.yaml << 'DCEOF'
# docker-compose.yaml v1.2.0
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

# Prometheus /metrics in app.py
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
        'aqi':  {'label':'aqi',   'data':[x['measurement']['aqi']    for x in measurement], 'backgroundColor':'#181d27','borderColor':'#181d27','borderWidth':3},
        'pm10': {'label':'pm10',  'data':[x['measurement']['pm10']   for x in measurement], 'backgroundColor':'#cc0000','borderColor':'#cc0000','borderWidth':3},
        'pm2':  {'label':'pm2.5', 'data':[x['measurement']['pm2.5'] for x in measurement], 'backgroundColor':'#42C0FB','borderColor':'#42C0FB','borderWidth':3},
    }

@app.route('/')
def index():
    return render_template('index.html', context={'historical': reconfigure_data(aqm.get_last_n_measurements())})

@app.route('/api/')
@cross_origin()
def api():
    return jsonify({'historical': reconfigure_data(aqm.get_last_n_measurements())})

@app.route('/api/now/')
def api_now():
    return jsonify({'current': aqm.get_measurement()})

@app.route('/metrics')
def metrics():
    """Prometheus text format endpoint."""
    try:
        data = aqm.get_last_n_measurements()
        if not data:
            return Response('# No data yet\n', mimetype='text/plain; version=0.0.4')
        latest = data[0]['measurement']
        ts_ms  = int(data[0]['time'] * 1000)
        out = (
            '# HELP aqi_index Air Quality Index (EPA)\n# TYPE aqi_index gauge\n'
            f'aqi_index {latest["aqi"]} {ts_ms}\n'
            '# HELP pm10_ugm3 PM10 ug/m3\n# TYPE pm10_ugm3 gauge\n'
            f'pm10_ugm3 {latest["pm10"]} {ts_ms}\n'
            '# HELP pm25_ugm3 PM2.5 ug/m3\n# TYPE pm25_ugm3 gauge\n'
            f'pm25_ugm3 {latest["pm2.5"]} {ts_ms}\n'
            '# HELP aqi_readings_total Total readings in Redis\n# TYPE aqi_readings_total counter\n'
            f'aqi_readings_total {len(data)}\n'
        )
        return Response(out, mimetype='text/plain; version=0.0.4')
    except Exception as e:
        return Response(f'# Error: {e}\n', mimetype='text/plain; version=0.0.4', status=500)

if __name__ == "__main__":
    app.run(debug=True, use_reloader=False, host='0.0.0.0',
            port=int(os.environ.get('PORT', '8000')))
PYEOF

# Update aqi_monitor.func: docker-compose -> docker compose
sed -i 's/docker-compose /docker compose /g' scripts/service/aqi_monitor.func

# Rebuild with compose V2 (or fall back)
sudo systemctl stop paqm.service 2>/dev/null || true
docker compose down 2>/dev/null || docker-compose down 2>/dev/null || true
docker compose build 2>/dev/null && DC="docker compose" || DC="docker-compose"

# Update and install systemd units
REAL_DIR=$(realpath ~/pi_air_quality_monitor)
REAL_USER=$(whoami)
sudo sed -i -e "s|\${REAL_DIR}|${REAL_DIR}|g" -e "s|\${REAL_USER}|${REAL_USER}|g" \
    /etc/systemd/system/paqm.service /etc/systemd/system/firefox-kiosk.service
sudo systemctl daemon-reload
sudo systemctl start paqm.service
sleep 20

source scripts/service/aqi_monitor.func
aqi_monitor status

# Test metrics
sleep 5
curl -sf http://localhost:8000/metrics | grep -E '^aqi|^pm' \
    && echo "  /metrics OK" || echo "  /metrics not ready yet"

# Add scrubbeer exclusion so it won't mangle setup scripts again
grep -q 'setup_v' .gitignore || echo 'setup_v*.sh' >> .gitignore
grep -q 'patch_' .gitignore  || echo 'patch_*.sh'  >> .gitignore

# Commit
git add -A
git commit -m "feat(v1.2.0-dev): config system, compose V2, metrics, no PII

- config.env.example committed, config.env gitignored
- All IPs/hostnames/paths scrubbed from tracked files
- docker-compose.yaml: V2 syntax, redis_data named volume, appendonly
- src/app.py: /metrics Prometheus endpoint
- aqi_monitor.func: docker compose V2
- Makefile: config.env aware, TARGET_HOST for copy/shell"

git push -u origin v1.2.0-dev
echo "Done — v1.2.0-dev pushed"
curl -s http://localhost:8000/metrics
