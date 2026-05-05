#!/usr/bin/env bash
cd ~/pi_air_quality_monitor

# Fix 1: Restore dark theme auto-refresh template
cat > src/templates/index.html << 'HTMLEOF'
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Raspberry Pi Air Quality Monitor</title>
    <!-- version: 1.2.0 -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.0.2/dist/css/bootstrap.min.css" rel="stylesheet"
        integrity="sha384-EVSTQN3/azprG1Anm3QDgpJLIm9Nao0Yz1ztcQTwFspd3yD65VohhpuuCOmLASjC" crossorigin="anonymous">
    <style>
        body { background: #0d1117; color: #e6edf3; }
        .container { padding-top: 1.5rem; }
        h1 { font-size: 1.4rem; font-weight: 500; margin-bottom: 0.25rem; }
        #status-bar { font-size: 0.8rem; color: #8b949e; margin-bottom: 1rem; }
        #status-dot { display: inline-block; width: 8px; height: 8px;
                      border-radius: 50%; background: #3fb950; margin-right: 6px;
                      animation: pulse 2s ease-in-out infinite; }
        @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }
        canvas { background: #161b22; border-radius: 8px; padding: 8px; }
    </style>
</head>
<body>
<div class="container">
    <div class="row">
        <div class="col-12">
            <h1>Raspberry Pi Air Quality Monitor</h1>
            <div id="status-bar">
                <span id="status-dot"></span>
                <span id="status-text">Loading...</span>
            </div>
        </div>
    </div>
    <div class="row">
        <div class="col-12">
            <canvas id="historicalChart"></canvas>
        </div>
    </div>
</div>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.0.2/dist/js/bootstrap.bundle.min.js"
    integrity="sha384-MrcW6ZMFYlzcLA8Nl+NtUVF0sA7MsXsP1UyJoMp4YLEuNSfAP+JcXn/tWtIaxVXM" crossorigin="anonymous"></script>
<script src="https://ajax.googleapis.com/ajax/libs/jquery/3.5.1/jquery.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.3.2/chart.min.js"
    integrity="sha512-VCHVc5miKoln972iJPvkQrUYYq7XpxXzvqNfiul1H4aZDwGBGC0lq373KNleaB2LpnC2a/iNfE5zoRYmB4TRDQ=="
    crossorigin="anonymous" referrerpolicy="no-referrer"></script>
<script>
const POLL_MS = 60000;
let chart = null;

function buildDatasets(data) {
    return {
        labels: data.historical.labels,
        datasets: [
            Object.assign({}, data.historical.aqi,  { tension: 0.3, pointRadius: 3 }),
            Object.assign({}, data.historical.pm10, { tension: 0.3, pointRadius: 3 }),
            Object.assign({}, data.historical.pm2,  { tension: 0.3, pointRadius: 3 }),
        ]
    };
}

function initChart(data) {
    const ctx = document.getElementById('historicalChart').getContext('2d');
    chart = new Chart(ctx, {
        type: 'line',
        data: buildDatasets(data),
        options: {
            responsive: true,
            animation: { duration: 400 },
            scales: {
                x: { ticks: { color: '#8b949e', maxTicksLimit: 10 }, grid: { color: '#21262d' } },
                y: { beginAtZero: true, ticks: { color: '#8b949e' }, grid: { color: '#21262d' } }
            },
            plugins: { legend: { labels: { color: '#e6edf3' } } }
        }
    });
}

function updateChart(data) {
    if (!chart) { initChart(data); return; }
    const ds = buildDatasets(data);
    chart.data.labels = ds.labels;
    chart.data.datasets.forEach((d, i) => { d.data = ds.datasets[i].data; });
    chart.update();
}

function setStatus(text, ok) {
    document.getElementById('status-text').textContent = text;
    document.getElementById('status-dot').style.background = ok ? '#3fb950' : '#f85149';
}

function fetchAndUpdate() {
    $.getJSON('/api/')
        .done(function(data) {
            updateChart(data);
            const latest = data.historical.labels.slice(-1)[0] || '—';
            setStatus('Last reading: ' + latest + ' · updates every 60s', true);
        })
        .fail(function() { setStatus('API unreachable — retrying...', false); });
}

fetchAndUpdate();
setInterval(fetchAndUpdate, POLL_MS);
</script>
</body>
</html>
HTMLEOF

# Fix 2: Add timezone mounts to docker-compose.yaml
cat > docker-compose.yaml << 'DCEOF'
# docker-compose.yaml v1.2.0
services:
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --save 60 1 --save 300 10 --appendonly yes
    volumes:
      - redis_data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
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
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    depends_on:
      redis:
        condition: service_healthy
    ports:
      - "${PAQM_PORT:-8000}:${PAQM_PORT:-8000}"
volumes:
  redis_data:
    driver: local
DCEOF

# Rebuild and restart to apply timezone + new template
docker compose down
docker compose build
sudo systemctl start paqm.service
sleep 20

source scripts/service/aqi_monitor.func
aqi_monitor status

# Commit all fixes
git add -A
git commit -m "fix(v1.2.0): restore dark/auto-refresh template, fix container timezone

- src/templates/index.html: restore dark theme + 60s auto-refresh (v1.2.0)
  (was reverted to original when branch cut from main)
- docker-compose.yaml: mount /etc/timezone and /etc/localtime into both
  containers so timestamps match system local time (was showing UTC,
  system is MDT UTC-6)
- scripts/service/aqi_monitor.func: pushd instead of cd to avoid clobbering
  caller's working directory"

git push origin v1.2.0-dev
echo "Done — check http://localhost:8000 for dark theme and local timestamps"
