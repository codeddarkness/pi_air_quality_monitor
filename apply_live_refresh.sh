#!/usr/bin/env bash
# =============================================================================
# apply_live_refresh.sh v0.2.1
# - Replaces index.html with auto-polling version (60s interval, no page reload)
# - Fixes aqi_monitor.func double-redirect log bug
# - Rebuilds docker image and restarts service
# =============================================================================

set -euo pipefail
REPO="${HOME}/pi_air_quality_monitor"
TEMPLATE="${REPO}/src/templates/index.html"
FUNC="${REPO}/scripts/service/aqi_monitor.func"
FUNC_ORIG="${REPO}/scripts/service/aqi_monitor.func"

cd "${REPO}"

log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "[\033[0;32mOK\033[0m] $*"; }

# ── 1. Backup originals ───────────────────────────────────────────────────────
log "Backing up originals..."
cp "${TEMPLATE}" "${TEMPLATE}.bak.$(date +%Y%m%d%H%M%S)"
ok "index.html backed up"

# ── 2. Write updated index.html ───────────────────────────────────────────────
log "Writing new index.html (v0.2.1)..."
cat > "${TEMPLATE}" << 'HTMLEOF'
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Raspberry Pi Air Quality Monitor</title>
    <!-- version: 0.2.1 -->
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
const POLL_INTERVAL_MS = 60000; // matches sensor collection interval
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
            plugins: {
                legend: { labels: { color: '#e6edf3' } }
            }
        }
    });
}

function updateChart(data) {
    if (!chart) { initChart(data); return; }
    const ds = buildDatasets(data);
    chart.data.labels = ds.labels;
    chart.data.datasets.forEach((dataset, i) => {
        dataset.data = ds.datasets[i].data;
    });
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
            setStatus('Last reading: ' + latest + ' · next update in 60s', true);
        })
        .fail(function() {
            setStatus('API unreachable — retrying...', false);
        });
}

// Initial load then poll
fetchAndUpdate();
setInterval(fetchAndUpdate, POLL_INTERVAL_MS);
</script>
</body>
</html>
HTMLEOF
ok "index.html written"

# ── 3. Fix aqi_monitor.func double-redirect bug ───────────────────────────────
# Bug: nohup docker-compose up > ${log} >/dev/null 2>&1
# Fix: nohup docker-compose up >> ${log} 2>&1
log "Patching aqi_monitor.func log redirect..."

# Work on the sourced copy (used at runtime via .bashrc)
BASHRC_FUNC="${HOME}/pi_air_quality_monitor/scripts/service/aqi_monitor.func"

for target in "${BASHRC_FUNC}"; do
    if [[ -f "${target}" ]]; then
        cp "${target}" "${target}.bak.$(date +%Y%m%d%H%M%S)"
        sed -i 's|nohup docker-compose up > \${log} >/dev/null 2>&1|nohup docker-compose up >> ${log} 2>\&1|g' "${target}"
        ok "Patched: ${target}"
    fi
done

# Also patch if it's in the repo root (legacy location checked by .bashrc)
LEGACY="${HOME}/pi_air_quality_monitor/aqi_monitor.func"
if [[ -f "${LEGACY}" ]]; then
    cp "${LEGACY}" "${LEGACY}.bak.$(date +%Y%m%d%H%M%S)"
    sed -i 's|nohup docker-compose up > \${log} >/dev/null 2>&1|nohup docker-compose up >> ${log} 2>\&1|g' "${LEGACY}"
    ok "Patched legacy: ${LEGACY}"
fi

# ── 4. Commit the changes ─────────────────────────────────────────────────────
log "Committing to custom_dev..."
git add src/templates/index.html scripts/service/aqi_monitor.func 2>/dev/null || true
git add -A
git commit -m "fix(v0.2.1): live auto-refresh chart + fix log redirect

- index.html: replace one-shot getJSON with 60s setInterval polling
- Chart updates in-place (no page reload), dark theme, status indicator
- aqi_monitor.func: fix double-redirect (> log >/dev/null) → >> log 2>&1
  so docker-compose output is actually captured in /tmp/sensor_logs/"

# ── 5. Rebuild and restart ────────────────────────────────────────────────────
log "Rebuilding docker image..."
docker-compose build

log "Restarting service..."
aqi_monitor restart 2>/dev/null || {
    docker-compose down 2>/dev/null || true
    sleep 2
    docker-compose up -d
}

sleep 5

log "Verifying..."
docker ps | grep -E 'pi-air|redis' && ok "Containers up" || echo "Check: docker ps"

echo
echo "======================================================================"
echo "  Done — v0.2.1 deployed"
echo "  Web UI  : http://$(hostname -I | awk '{print $1}'):8000"
echo "  API     : http://$(hostname -I | awk '{print $1}'):8000/api/"
echo "  Logs    : tail -f /tmp/sensor_logs/aqi_monitor.log"
echo "======================================================================"
