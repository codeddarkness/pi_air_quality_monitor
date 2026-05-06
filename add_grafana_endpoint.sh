#!/usr/bin/env bash
# add_grafana_endpoint.sh v1.3.1
# - Adds /api/grafana/ row-oriented JSON endpoint to Flask
# - Rebuilds docker image and restarts stack
# - Commits to v1.3.0-dev
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO}"
source config.env 2>/dev/null || true

log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "  [\033[0;32mOK\033[0m] $*"; }

git checkout v1.3.0-dev 2>/dev/null || true

# ── 1. Rewrite src/app.py cleanly with /api/grafana/ included ────────────────
log "Writing src/app.py with /api/grafana/ endpoint..."
cat > src/app.py << 'PYEOF'
# app.py v1.3.1
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
        'aqi':  {'label': 'aqi',   'data': [x['measurement']['aqi']    for x in measurement],
                 'backgroundColor': '#f0b429', 'borderColor': '#f0b429', 'borderWidth': 3},
        'pm10': {'label': 'pm10',  'data': [x['measurement']['pm10']   for x in measurement],
                 'backgroundColor': '#ff6b6b', 'borderColor': '#ff6b6b', 'borderWidth': 3},
        'pm2':  {'label': 'pm2.5', 'data': [x['measurement']['pm2.5'] for x in measurement],
                 'backgroundColor': '#42C0FB', 'borderColor': '#42C0FB', 'borderWidth': 3},
    }


@app.route('/')
def index():
    return render_template('index.html',
        context={'historical': reconfigure_data(aqm.get_last_n_measurements())})


@app.route('/api/')
@cross_origin()
def api():
    """Historical data in Chart.js format (last 30 readings)."""
    return jsonify({'historical': reconfigure_data(aqm.get_last_n_measurements())})


@app.route('/api/now/')
@cross_origin()
def api_now():
    """Single live reading from sensor."""
    return jsonify({'current': aqm.get_measurement()})


@app.route('/api/grafana/')
@cross_origin()
def api_grafana():
    """Row-oriented JSON for Grafana Infinity datasource.

    Returns an array of objects with timestamp, aqi, pm10, pm25.
    Each row is one sensor reading, ordered oldest to newest.

    Example row:
        {"timestamp": "2026-05-05 19:22:39", "aqi": 7, "pm10": 3.3, "pm25": 1.6}

    Grafana Infinity setup:
        Type: JSON | Parser: Default | Format: Table
        Rows/Root: $[*]
        Columns: timestamp (Time), aqi (Number), pm10 (Number), pm25 (Number)
    """
    data = reconfigure_data(aqm.get_last_n_measurements())
    rows = [
        {
            'timestamp': ts,
            'aqi':  data['aqi']['data'][i],
            'pm10': data['pm10']['data'][i],
            'pm25': data['pm2']['data'][i],
        }
        for i, ts in enumerate(data['labels'])
    ]
    return jsonify(rows)


@app.route('/metrics')
def metrics():
    """Prometheus text format — scrape target for Prometheus or Grafana HTTP datasource."""
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
            '# HELP aqi_readings_total Total readings stored in Redis\n'
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
ok "src/app.py written"

# ── 2. Rebuild image (restart alone does not pick up code changes) ────────────
log "Stopping stack..."
docker compose down 2>/dev/null || true

log "Building image..."
docker compose build
ok "Image built"

log "Starting paqm.service..."
sudo systemctl start paqm.service 2>/dev/null || docker compose up -d

log "Waiting for web container..."
for i in $(seq 1 30); do
    WEB=$(docker ps --filter "name=pi_air_quality_monitor" --filter "name=web" \
        --format "{{.Names}}" 2>/dev/null | head -1 || true)
    [[ -n "${WEB}" ]] && { ok "Container: ${WEB}"; break; }
    sleep 4
done

log "Waiting for Flask API..."
for i in $(seq 1 20); do
    curl -sf http://localhost:8000/api/ >/dev/null 2>&1 && { ok "API ready"; break; }
    sleep 3
done

# ── 3. Validate all endpoints ─────────────────────────────────────────────────
log "Validating endpoints..."
PASS=0; FAIL=0
chk() { [[ "$1" == "ok" ]] && { echo "  [PASS] $2"; ((++PASS)); } || { echo "  [FAIL] $2"; ((++FAIL)); }; }

# /api/
API=$(curl -sf http://localhost:8000/api/ 2>/dev/null || echo "")
echo "${API}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'historical' in d" 2>/dev/null \
    && chk ok "/api/ responding" || chk fail "/api/ not responding"

# /api/now/
NOW=$(curl -sf http://localhost:8000/api/now/ 2>/dev/null || echo "")
echo "${NOW}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'current' in d" 2>/dev/null \
    && chk ok "/api/now/ responding" || chk fail "/api/now/ not responding"

# /api/grafana/
GRAF=$(curl -sf http://localhost:8000/api/grafana/ 2>/dev/null || echo "")
echo "${GRAF}" | python3 -c "
import json, sys
rows = json.load(sys.stdin)
assert isinstance(rows, list), 'not a list'
assert len(rows) > 0, 'empty list'
assert all(k in rows[0] for k in ('timestamp','aqi','pm10','pm25')), 'missing keys'
print(f'  {len(rows)} rows, keys: {list(rows[0].keys())}')
" 2>/dev/null && chk ok "/api/grafana/ row-oriented JSON" || chk fail "/api/grafana/ failed"

# /metrics
curl -sf http://localhost:8000/metrics | grep -q 'aqi_index' \
    && chk ok "/metrics Prometheus format" || chk fail "/metrics not responding"

echo
echo "  ${PASS} passed  ${FAIL} failed"
[[ "${FAIL}" -gt 0 ]] && { echo "  Fix failures before committing"; exit 1; }

# ── 4. Show sample grafana response ──────────────────────────────────────────
log "Sample /api/grafana/ output (last 3 rows):"
curl -sf http://localhost:8000/api/grafana/ | python3 -c "
import json, sys
rows = json.load(sys.stdin)
for r in rows[-3:]:
    print(f'  {r}')
print(f'  Total: {len(rows)} rows')
"

# ── 5. Update CHANGELOG ───────────────────────────────────────────────────────
log "Updating CHANGELOG..."
python3 - << 'PYEOF'
import datetime
path = 'CHANGELOG.md'
content = open(path).read()
today = datetime.date.today().isoformat()
entry = f"""## [1.3.1] - {today}
### Added
- /api/grafana/ endpoint: row-oriented JSON for Grafana Infinity datasource
  Returns array of objects: timestamp, aqi, pm10, pm25
  Ordered oldest to newest, last 30 readings
  Grafana setup: Type=JSON, Parser=Default, Format=Table, Rows/Root=$[*]

### Fixed
- AQI backgroundColor/borderColor updated to #f0b429 in reconfigure_data()
  (was still #181d27 in the API response color metadata)
- docker compose restart replaced with down+build+up in deploy scripts
  (restart does not rebuild image, so code changes were not picked up)

"""
if '[1.3.1]' not in content:
    content = content.replace('# Changelog\n', f'# Changelog\n\n{entry}')
    open(path, 'w').write(content)
    print('OK: CHANGELOG updated')
else:
    print('OK: already present')
PYEOF

# ── 6. Commit and push ────────────────────────────────────────────────────────
log "Committing..."
echo "1.3.1" > VERSION
git add -A
git commit -m "feat(v1.3.1): /api/grafana/ row-oriented endpoint

- GET /api/grafana/ returns [{timestamp, aqi, pm10, pm25}, ...]
  (last 30 readings, oldest first — ready for Grafana Infinity)
- Fix reconfigure_data() AQI color metadata: #181d27 -> #f0b429
- Rebuild image properly (down + build + up, not restart)

Grafana Infinity panel config:
  URL     : http://<pi-ip>:8000/api/grafana/
  Type    : JSON
  Parser  : Default
  Format  : Table
  Rows    : dollar-sign[*]
  Columns : timestamp (Time), aqi (Number), pm10 (Number), pm25 (Number)"

git push origin v1.3.0-dev
ok "Pushed to v1.3.0-dev"

echo
echo "============================================================"
echo "  v1.3.1 deployed"
echo
echo "  Endpoints:"
echo "    /api/         Chart.js format (existing)"
echo "    /api/now/     Single live reading"
echo "    /api/grafana/ Row JSON for Infinity (NEW)"
echo "    /metrics      Prometheus text format"
echo
echo "  Grafana Infinity panel setup:"
echo "    URL    : http://$(hostname -I | awk '{print $1}'):8000/api/grafana/"
echo "    Type   : JSON"
echo "    Parser : Default"
echo "    Format : Table"
echo "    Root   : \$[*]"
echo "    Columns:"
echo "      timestamp -> Time"
echo "      aqi       -> Number"
echo "      pm10      -> Number"
echo "      pm25      -> Number"
echo "============================================================"
