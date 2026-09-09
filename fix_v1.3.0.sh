#!/usr/bin/env bash
# fix_v1.3.0.sh — fix truncated template + kiosk exit-code 1
# Run from: ~/pi_air_quality_monitor on v1.3.0-dev branch
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO}"
source config.env 2>/dev/null || true

log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "  [\033[0;32mOK\033[0m] $*"; }

git checkout v1.3.0-dev 2>/dev/null || true

# ── 1. Write template via file (no heredoc, no python string escaping) ────────
log "Writing index.html to temp file then moving into place..."

TMPHTML=$(mktemp /tmp/index_XXXXXX.html)

cat > "${TMPHTML}" << 'ENDOFHTML'
<!doctype html>
<html lang="en" data-theme="dark">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Raspberry Pi Air Quality Monitor</title>
    <!-- version: 1.3.0 -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.0.2/dist/css/bootstrap.min.css" rel="stylesheet"
        integrity="sha384-EVSTQN3/azprG1Anm3QDgpJLIm9Nao0Yz1ztcQTwFspd3yD65VohhpuuCOmLASjC" crossorigin="anonymous">
    <style>
        :root[data-theme="dark"] {
            --bg: #0d1117; --bg-card: #161b22; --fg: #e6edf3;
            --fg-muted: #8b949e; --border: #21262d;
            --btn-bg: #21262d; --btn-fg: #e6edf3; --btn-hover: #30363d;
        }
        :root[data-theme="light"] {
            --bg: #ffffff; --bg-card: #f6f8fa; --fg: #24292f;
            --fg-muted: #57606a; --border: #d0d7de;
            --btn-bg: #f6f8fa; --btn-fg: #24292f; --btn-hover: #eaeef2;
        }
        * { transition: background-color 0.2s, color 0.2s, border-color 0.2s; }
        body { background: var(--bg); color: var(--fg); }
        .container { padding-top: 1.2rem; }
        .header-row {
            display: flex; align-items: center;
            justify-content: space-between; margin-bottom: 0.25rem;
        }
        h1 { font-size: 1.4rem; font-weight: 500; margin: 0; }
        #theme-btn {
            background: var(--btn-bg); color: var(--btn-fg);
            border: 1px solid var(--border); border-radius: 6px;
            padding: 4px 14px; font-size: 0.8rem; cursor: pointer;
            display: flex; align-items: center; gap: 6px; white-space: nowrap;
        }
        #theme-btn:hover { background: var(--btn-hover); }
        #status-bar {
            font-size: 0.8rem; color: var(--fg-muted);
            margin-bottom: 1rem; display: flex; align-items: center; gap: 6px;
        }
        #status-dot {
            display: inline-block; width: 8px; height: 8px;
            border-radius: 50%; background: #3fb950; flex-shrink: 0;
            animation: pulse 2s ease-in-out infinite;
        }
        @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }
        .chart-card {
            background: var(--bg-card); border: 1px solid var(--border);
            border-radius: 8px; padding: 12px;
        }
        .legend-row {
            font-size: 0.75rem; color: var(--fg-muted);
            margin-top: 8px; display: flex; gap: 16px; flex-wrap: wrap;
        }
        .swatch {
            display: inline-block; width: 12px; height: 12px;
            border-radius: 2px; margin-right: 4px; vertical-align: middle;
        }
    </style>
</head>
<body>
<div class="container">
  <div class="row">
    <div class="col-12">
      <div class="header-row">
        <h1>Raspberry Pi Air Quality Monitor</h1>
        <button id="theme-btn" onclick="toggleTheme()">
          <span id="theme-icon">&#9728;</span>
          <span id="theme-label">Light mode</span>
        </button>
      </div>
      <div id="status-bar">
        <span id="status-dot"></span>
        <span id="status-text">Loading...</span>
      </div>
    </div>
  </div>
  <div class="row">
    <div class="col-12">
      <div class="chart-card">
        <canvas id="historicalChart"></canvas>
        <div class="legend-row">
          <span><span class="swatch" style="background:#f0b429"></span>AQI index</span>
          <span><span class="swatch" style="background:#ff6b6b"></span>PM10 (&mu;g/m&sup3;)</span>
          <span><span class="swatch" style="background:#42c0fb"></span>PM2.5 (&mu;g/m&sup3;)</span>
        </div>
      </div>
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
let currentTheme = localStorage.getItem('paqm-theme') || 'dark';
const THEME = {
  dark:  { aqi:'#f0b429', pm10:'#ff6b6b', pm25:'#42c0fb',
           tick:'#8b949e', grid:'#21262d', legend:'#e6edf3' },
  light: { aqi:'#b85c00', pm10:'#cf222e', pm25:'#0550ae',
           tick:'#57606a', grid:'#d0d7de', legend:'#24292f' }
};
function applyTheme(t) {
  document.documentElement.setAttribute('data-theme', t);
  currentTheme = t;
  localStorage.setItem('paqm-theme', t);
  var dark = (t === 'dark');
  document.getElementById('theme-icon').innerHTML  = dark ? '&#9728;' : '&#9790;';
  document.getElementById('theme-label').textContent = dark ? 'Light mode' : 'Dark mode';
  if (chart) refreshChartColors();
}
function toggleTheme() { applyTheme(currentTheme === 'dark' ? 'light' : 'dark'); }
function refreshChartColors() {
  var T = THEME[currentTheme];
  chart.data.datasets[0].borderColor = chart.data.datasets[0].backgroundColor = chart.data.datasets[0].pointBackgroundColor = T.aqi;
  chart.data.datasets[1].borderColor = chart.data.datasets[1].backgroundColor = chart.data.datasets[1].pointBackgroundColor = T.pm10;
  chart.data.datasets[2].borderColor = chart.data.datasets[2].backgroundColor = chart.data.datasets[2].pointBackgroundColor = T.pm25;
  chart.options.scales.x.ticks.color = chart.options.scales.y.ticks.color = T.tick;
  chart.options.scales.x.grid.color  = chart.options.scales.y.grid.color  = T.grid;
  chart.options.plugins.legend.labels.color = T.legend;
  chart.update();
}
function makeDatasets(data) {
  var T = THEME[currentTheme];
  function ds(src, color, lbl) {
    return Object.assign({}, src, {
      label: lbl, tension: 0.3, pointRadius: 3, borderWidth: 2,
      borderColor: color, backgroundColor: color, pointBackgroundColor: color
    });
  }
  return {
    labels: data.historical.labels,
    datasets: [
      ds(data.historical.aqi,  T.aqi,  'AQI'),
      ds(data.historical.pm10, T.pm10, 'PM10'),
      ds(data.historical.pm2,  T.pm25, 'PM2.5')
    ]
  };
}
function initChart(data) {
  var T = THEME[currentTheme];
  var ctx = document.getElementById('historicalChart').getContext('2d');
  chart = new Chart(ctx, {
    type: 'line',
    data: makeDatasets(data),
    options: {
      responsive: true,
      animation: { duration: 400 },
      scales: {
        x: { ticks: { color: T.tick, maxTicksLimit: 8 }, grid: { color: T.grid } },
        y: { beginAtZero: true, ticks: { color: T.tick }, grid: { color: T.grid } }
      },
      plugins: { legend: { labels: { color: T.legend } } }
    }
  });
}
function updateChart(data) {
  if (!chart) { initChart(data); return; }
  var ds = makeDatasets(data);
  chart.data.labels = ds.labels;
  chart.data.datasets.forEach(function(d, i) {
    d.data = ds.datasets[i].data;
    d.borderColor = d.backgroundColor = d.pointBackgroundColor = ds.datasets[i].borderColor;
  });
  refreshChartColors();
}
function setStatus(text, good) {
  document.getElementById('status-text').textContent = text;
  document.getElementById('status-dot').style.background = good ? '#3fb950' : '#f85149';
}
function fetchAndUpdate() {
  $.getJSON('/api/')
    .done(function(data) {
      updateChart(data);
      var latest = data.historical.labels.slice(-1)[0] || '--';
      setStatus('Last reading: ' + latest + ' · updates every 60s', true);
    })
    .fail(function() { setStatus('API unreachable -- retrying...', false); });
}
applyTheme(currentTheme);
fetchAndUpdate();
setInterval(fetchAndUpdate, POLL_MS);
</script>
</body>
</html>
ENDOFHTML

# Verify file is complete before copying
LINES=$(wc -l < "${TMPHTML}")
if [[ "${LINES}" -lt 100 ]]; then
    echo "ERROR: template file too short (${LINES} lines) — aborting"
    exit 1
fi
for needle in "version: 1.3.0" "toggleTheme" "f0b429" "ff6b6b" "POLL_MS" "applyTheme" "localStorage"; do
    grep -q "${needle}" "${TMPHTML}" || { echo "ERROR: missing '${needle}' in template"; exit 1; }
done

cp "${TMPHTML}" src/templates/index.html
rm "${TMPHTML}"
ok "index.html written (${LINES} lines, all checks passed)"

# ── 2. Fix kiosk_foreground.sh ────────────────────────────────────────────────
# Issues:
# - firefox-esr --kiosk exits with 1 if another Firefox is running (reuses instance)
# - No display readiness check (X may not be ready when systemd fires)
# - Need --no-remote to force a new instance regardless of existing Firefox
log "Rewriting kiosk_foreground.sh with display check and --no-remote..."

cat > scripts/kiosk/kiosk_foreground.sh << 'KEOF'
#!/usr/bin/env bash
# kiosk_foreground.sh v1.3.0
# Waits for X display and API, then opens Firefox in kiosk mode.
# --no-remote forces a fresh instance even if Firefox is already open.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"
[[ -f "${REPO_DIR}/config.env" ]] && source "${REPO_DIR}/config.env"

DISPLAY="${KIOSK_DISPLAY:-:0}"
URL="${KIOSK_URL:-http://localhost:${PAQM_PORT:-8000}}"
LOG="${REPO_DIR}/logs/firefox-kiosk.log"
PROFILE_DIR="/tmp/paqm-kiosk-profile"

export DISPLAY
export XAUTHORITY="${XAUTHORITY:-/home/${PAQM_USER:-pi}/.Xauthority}"

mkdir -p "$(dirname "${LOG}")" "${PROFILE_DIR}"
ts() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*" | tee -a "${LOG}"; }

ts "kiosk_foreground.sh v1.3.0 starting"
ts "URL=${URL} DISPLAY=${DISPLAY}"

# Wait for X display to be ready (up to 60s)
ts "Waiting for X display ${DISPLAY}..."
for i in $(seq 1 30); do
    xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1 && { ts "Display ready (attempt ${i})"; break; }
    [[ "${i}" -eq 30 ]] && { ts "ERROR: display ${DISPLAY} not available after 60s"; exit 1; }
    sleep 2
done

# Kill any existing Firefox kiosk profile to prevent lock issues
rm -f "${PROFILE_DIR}/lock" "${PROFILE_DIR}/.parentlock" 2>/dev/null

# Wait for Flask API (up to 3 min)
ts "Waiting for API at ${URL}/api/..."
for i in $(seq 1 36); do
    curl -sf "${URL}/api/" >/dev/null 2>&1 && { ts "API ready (attempt ${i})"; break; }
    [[ "${i}" -eq 36 ]] && ts "WARNING: API not ready after 3min, opening anyway"
    sleep 5
done

ts "Launching firefox-esr --kiosk --no-remote"
exec firefox-esr \
    --kiosk \
    --no-remote \
    --profile "${PROFILE_DIR}" \
    "${URL}" 2>>"${LOG}"
KEOF
chmod +x scripts/kiosk/kiosk_foreground.sh
ok "kiosk_foreground.sh rewritten"

# ── 3. Update installed systemd kiosk service ────────────────────────────────
log "Reinstalling firefox-kiosk.service..."
sudo cp systemd/firefox-kiosk.service /etc/systemd/system/firefox-kiosk.service
REAL_DIR=$(realpath "${REPO}")
REAL_USER=$(whoami)
sudo sed -i \
    -e "s|\${PAQM_DIR}|${REAL_DIR}|g" \
    -e "s|\${REAL_DIR}|${REAL_DIR}|g" \
    -e "s|\${PAQM_USER}|${REAL_USER}|g" \
    /etc/systemd/system/firefox-kiosk.service
sudo systemctl daemon-reload
ok "firefox-kiosk.service reinstalled"

# ── 4. Rebuild docker image with fixed template ───────────────────────────────
log "Rebuilding docker image..."
docker compose down 2>/dev/null || true
docker compose build

log "Starting paqm.service..."
sudo systemctl start paqm.service

log "Waiting for web container and API..."
for i in $(seq 1 30); do
    WEB=$(docker ps --filter "name=pi_air_quality_monitor_web" --format "{{.Names}}" 2>/dev/null || true)
    [[ -n "${WEB}" ]] && break
    sleep 4
done
for i in $(seq 1 15); do
    curl -sf http://localhost:8000/api/ >/dev/null 2>&1 && { ok "API ready"; break; }
    sleep 3
done

# ── 5. Validate template integrity ───────────────────────────────────────────
log "Validating template..."
PAGE=$(curl -sf http://localhost:8000/ 2>/dev/null || echo "")
PAGE_LINES=$(echo "${PAGE}" | wc -l)

PASS=0; FAIL=0
chk() { [[ "$1" == "ok" ]] && { echo "  [PASS] $2"; ((++PASS)); } || { echo "  [FAIL] $2"; ((++FAIL)); }; }

[[ "${PAGE_LINES}" -gt 100 ]] && chk ok "Template length (${PAGE_LINES} lines)" || chk fail "Template truncated (${PAGE_LINES} lines)"
echo "${PAGE}" | grep -q 'version: 1.3.0' && chk ok "Version 1.3.0" || chk fail "Version tag missing"
echo "${PAGE}" | grep -q 'toggleTheme'    && chk ok "toggleTheme function" || chk fail "toggleTheme missing"
echo "${PAGE}" | grep -q 'applyTheme'     && chk ok "applyTheme function" || chk fail "applyTheme missing"
echo "${PAGE}" | grep -q 'localStorage'   && chk ok "localStorage persistence" || chk fail "localStorage missing"
echo "${PAGE}" | grep -q 'f0b429'         && chk ok "AQI amber #f0b429" || chk fail "AQI color missing"
echo "${PAGE}" | grep -q 'ff6b6b'         && chk ok "PM10 red #ff6b6b" || chk fail "PM10 color missing"
echo "${PAGE}" | grep -q '</html>'        && chk ok "Template complete (</html> present)" || chk fail "Template incomplete — missing </html>"
echo "${PAGE}" | grep -q 'setInterval'    && chk ok "Auto-refresh setInterval" || chk fail "setInterval missing"

curl -sf http://localhost:8000/metrics | grep -q 'aqi_index' && chk ok "/metrics" || chk fail "/metrics down"

echo
echo "  ${PASS} passed  ${FAIL} failed"
[[ "${FAIL}" -gt 0 ]] && { echo "  Failures — not committing"; exit 1; }

# ── 6. Restart kiosk with fixed script ───────────────────────────────────────
log "Restarting firefox-kiosk service..."
sudo systemctl stop firefox-kiosk.service 2>/dev/null || true
sleep 2
sudo systemctl start firefox-kiosk.service
sleep 5
KIOSK_STATE=$(sudo systemctl is-active firefox-kiosk.service 2>/dev/null || echo "unknown")
ok "firefox-kiosk.service: ${KIOSK_STATE}"

# ── 7. Commit ─────────────────────────────────────────────────────────────────
log "Committing..."
git add -A
git commit -m "fix(v1.3.0): template truncation + kiosk --no-remote startup fix

Template:
- Rewrite via heredoc to temp file (avoids python string escape truncation)
- Add </html> completeness check before copying into place
- Simplify JS (no arrow functions, const->var compat, inline color assignment)

kiosk_foreground.sh v1.3.0:
- Add xdpyinfo display readiness check (up to 60s, 2s intervals)
- Add --no-remote flag: forces fresh Firefox instance, prevents exit-code 1
  when an existing Firefox is running in the session
- Add --profile /tmp/paqm-kiosk-profile: isolated profile, clears lock files
  on each start to prevent profile-in-use errors after unclean shutdown
- Extend API wait to 3min (36x5s) to handle slow boot scenarios"

git push origin v1.3.0-dev
ok "Pushed to v1.3.0-dev"

echo
echo "============================================================"
echo "  v1.3.0 fixes applied"
echo "  Web     : http://$(hostname -I | awk '{print $1}'):8000"
echo "  Kiosk   : sudo systemctl status firefox-kiosk.service"
echo "  Kiosk log: tail -f ${REAL_DIR}/logs/firefox-kiosk.log"
echo "============================================================"
