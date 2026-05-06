#!/usr/bin/env bash
# =============================================================================
# setup_v1.3.0.sh
# - Creates v1.3.0-dev branch
# - Fix AQI line color (was #181d27 — invisible on dark background)
# - Add light/dark mode toggle button to web UI
# - Update README roadmap sections
# =============================================================================

set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO}"
source config.env 2>/dev/null || true

log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "  [\033[0;32mOK\033[0m] $*"; }

# ── 0. Branch ─────────────────────────────────────────────────────────────────
log "Creating v1.3.0-dev from main..."
git checkout main && git pull origin main
git checkout -b v1.3.0-dev 2>/dev/null || git checkout v1.3.0-dev
echo "1.3.0-dev" > VERSION
ok "Branch: v1.3.0-dev"

# ── 1. Write new index.html ───────────────────────────────────────────────────
log "Writing updated index.html v1.3.0..."
python3 - << 'PYEOF'
template = '''<!doctype html>
<html lang="en" data-theme="dark">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Raspberry Pi Air Quality Monitor</title>
    <!-- version: 1.3.0 -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.0.2/dist/css/bootstrap.min.css" rel="stylesheet"
        integrity="sha384-EVSTQN3/azprG1Anm3QDgpJLIm9Nao0Yz1ztcQTwFspd3yD65VohhpuuCOmLASjC" crossorigin="anonymous">
    <style>
        /* ── Theme variables ── */
        :root[data-theme="dark"] {
            --bg:         #0d1117;
            --bg-card:    #161b22;
            --fg:         #e6edf3;
            --fg-muted:   #8b949e;
            --border:     #21262d;
            --btn-bg:     #21262d;
            --btn-fg:     #e6edf3;
            --btn-hover:  #30363d;
            --aqi-color:  #f0b429;
            --pm10-color: #ff6b6b;
            --pm25-color: #42c0fb;
        }
        :root[data-theme="light"] {
            --bg:         #ffffff;
            --bg-card:    #f6f8fa;
            --fg:         #24292f;
            --fg-muted:   #57606a;
            --border:     #d0d7de;
            --btn-bg:     #f6f8fa;
            --btn-fg:     #24292f;
            --btn-hover:  #eaeef2;
            --aqi-color:  #b85c00;
            --pm10-color: #cf222e;
            --pm25-color: #0550ae;
        }

        * { transition: background-color 0.2s, color 0.2s, border-color 0.2s; }

        body {
            background: var(--bg);
            color: var(--fg);
        }
        .container { padding-top: 1.2rem; }

        /* ── Header row ── */
        .header-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 0.25rem;
        }
        h1 {
            font-size: 1.4rem;
            font-weight: 500;
            margin: 0;
        }

        /* ── Theme toggle button ── */
        #theme-btn {
            background: var(--btn-bg);
            color: var(--btn-fg);
            border: 1px solid var(--border);
            border-radius: 6px;
            padding: 4px 12px;
            font-size: 0.8rem;
            cursor: pointer;
            display: flex;
            align-items: center;
            gap: 6px;
            white-space: nowrap;
        }
        #theme-btn:hover { background: var(--btn-hover); }
        #theme-icon { font-size: 14px; }

        /* ── Status bar ── */
        #status-bar {
            font-size: 0.8rem;
            color: var(--fg-muted);
            margin-bottom: 1rem;
            display: flex;
            align-items: center;
            gap: 6px;
        }
        #status-dot {
            display: inline-block;
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: #3fb950;
            flex-shrink: 0;
            animation: pulse 2s ease-in-out infinite;
        }
        @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }

        /* ── Chart card ── */
        .chart-card {
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 12px;
        }

        /* ── Legend color swatches ── */
        .legend-swatch {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 2px;
            margin-right: 4px;
            vertical-align: middle;
        }
        .legend-row {
            font-size: 0.75rem;
            color: var(--fg-muted);
            margin-top: 8px;
            display: flex;
            gap: 16px;
            flex-wrap: wrap;
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
                    <span><span class="legend-swatch" style="background:#f0b429"></span>AQI index</span>
                    <span><span class="legend-swatch" style="background:#ff6b6b"></span>PM10 (&mu;g/m&sup3;)</span>
                    <span><span class="legend-swatch" style="background:#42c0fb"></span>PM2.5 (&mu;g/m&sup3;)</span>
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

// ── Theme colors per mode ──────────────────────────────────────────────────
const THEME = {
    dark: {
        aqi:    { border: '#f0b429', bg: '#f0b429' },
        pm10:   { border: '#ff6b6b', bg: '#ff6b6b' },
        pm25:   { border: '#42c0fb', bg: '#42c0fb' },
        tick:   '#8b949e',
        grid:   '#21262d',
        legend: '#e6edf3',
    },
    light: {
        aqi:    { border: '#b85c00', bg: '#b85c00' },
        pm10:   { border: '#cf222e', bg: '#cf222e' },
        pm25:   { border: '#0550ae', bg: '#0550ae' },
        tick:   '#57606a',
        grid:   '#d0d7de',
        legend: '#24292f',
    }
};

function applyTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    currentTheme = theme;
    localStorage.setItem('paqm-theme', theme);
    const isDark = theme === 'dark';
    document.getElementById('theme-icon').innerHTML  = isDark ? '&#9728;' : '&#9790;';
    document.getElementById('theme-label').textContent = isDark ? 'Light mode' : 'Dark mode';
    if (chart) updateChartTheme(theme);
}

function toggleTheme() {
    applyTheme(currentTheme === 'dark' ? 'light' : 'dark');
}

function updateChartTheme(theme) {
    const T = THEME[theme];
    chart.data.datasets[0].borderColor     = T.aqi.border;
    chart.data.datasets[0].backgroundColor = T.aqi.bg;
    chart.data.datasets[0].pointBackgroundColor = T.aqi.border;
    chart.data.datasets[1].borderColor     = T.pm10.border;
    chart.data.datasets[1].backgroundColor = T.pm10.bg;
    chart.data.datasets[1].pointBackgroundColor = T.pm10.border;
    chart.data.datasets[2].borderColor     = T.pm25.border;
    chart.data.datasets[2].backgroundColor = T.pm25.bg;
    chart.data.datasets[2].pointBackgroundColor = T.pm25.border;
    chart.options.scales.x.ticks.color  = T.tick;
    chart.options.scales.x.grid.color   = T.grid;
    chart.options.scales.y.ticks.color  = T.tick;
    chart.options.scales.y.grid.color   = T.grid;
    chart.options.plugins.legend.labels.color = T.legend;
    chart.update();
}

function buildDatasets(data) {
    const T = THEME[currentTheme];
    return {
        labels: data.historical.labels,
        datasets: [
            Object.assign({}, data.historical.aqi, {
                label: 'AQI',
                tension: 0.3,
                pointRadius: 3,
                borderWidth: 2,
                borderColor: T.aqi.border,
                backgroundColor: T.aqi.bg,
                pointBackgroundColor: T.aqi.border,
            }),
            Object.assign({}, data.historical.pm10, {
                label: 'PM10',
                tension: 0.3,
                pointRadius: 3,
                borderWidth: 2,
                borderColor: T.pm10.border,
                backgroundColor: T.pm10.bg,
                pointBackgroundColor: T.pm10.border,
            }),
            Object.assign({}, data.historical.pm2, {
                label: 'PM2.5',
                tension: 0.3,
                pointRadius: 3,
                borderWidth: 2,
                borderColor: T.pm25.border,
                backgroundColor: T.pm25.bg,
                pointBackgroundColor: T.pm25.border,
            }),
        ]
    };
}

function initChart(data) {
    const T = THEME[currentTheme];
    const ctx = document.getElementById('historicalChart').getContext('2d');
    chart = new Chart(ctx, {
        type: 'line',
        data: buildDatasets(data),
        options: {
            responsive: true,
            animation: { duration: 400 },
            scales: {
                x: {
                    ticks: { color: T.tick, maxTicksLimit: 8 },
                    grid:  { color: T.grid }
                },
                y: {
                    beginAtZero: true,
                    ticks: { color: T.tick },
                    grid:  { color: T.grid }
                }
            },
            plugins: {
                legend: { labels: { color: T.legend } }
            }
        }
    });
}

function updateChart(data) {
    if (!chart) { initChart(data); return; }
    const ds = buildDatasets(data);
    chart.data.labels = ds.labels;
    chart.data.datasets.forEach((d, i) => {
        d.data             = ds.datasets[i].data;
        d.borderColor      = ds.datasets[i].borderColor;
        d.backgroundColor  = ds.datasets[i].backgroundColor;
        d.pointBackgroundColor = ds.datasets[i].pointBackgroundColor;
    });
    updateChartTheme(currentTheme);
}

function setStatus(text, good) {
    document.getElementById('status-text').textContent = text;
    document.getElementById('status-dot').style.background = good ? '#3fb950' : '#f85149';
}

function fetchAndUpdate() {
    $.getJSON('/api/')
        .done(function(data) {
            updateChart(data);
            const latest = data.historical.labels.slice(-1)[0] || '--';
            setStatus('Last reading: ' + latest + ' · updates every 60s', true);
        })
        .fail(function() { setStatus('API unreachable -- retrying...', false); });
}

// Init
applyTheme(currentTheme);
fetchAndUpdate();
setInterval(fetchAndUpdate, POLL_MS);
</script>
</body>
</html>'''

with open('src/templates/index.html', 'w') as f:
    f.write(template)

# Verify
checks = ['version: 1.3.0', 'POLL_MS', 'buildDatasets', 'toggleTheme',
          'f0b429', 'ff6b6b', '42c0fb', 'data-theme', 'localStorage',
          'Light mode', 'Dark mode']
t = open('src/templates/index.html').read()
for c in checks:
    assert c in t, f'MISSING: {c}'
print('OK: index.html v1.3.0 written and verified')
PYEOF
ok "index.html written"

# ── 2. Update app.py — fix AQI color in API response ─────────────────────────
# The API embeds colors in the JSON; the frontend overrides them,
# but update the defaults so /api/ output is also accurate.
log "Updating AQI color in src/app.py API response..."
sed -i "s/'backgroundColor':'#181d27','borderColor':'#181d27'/'backgroundColor':'#f0b429','borderColor':'#f0b429'/" src/app.py
ok "app.py AQI color updated (#181d27 → #f0b429)"

# ── 3. Update README roadmap ──────────────────────────────────────────────────
log "Updating README roadmap..."
python3 - << 'PYEOF'
content = open('README.md').read()

old_roadmap = '''## Roadmap (v1.3.0)

- [ ] Grafana dashboard JSON export for one-click import
- [ ] Persist Grafana dashboards across container restarts
- [ ] Alert threshold config in config.env (notify when AQI exceeds N)
- [ ] Historical data export endpoint (/api/export.csv)'''

new_roadmap = '''## Roadmap

### v1.3.0 (current dev)
- [x] AQI line color: #181d27 (invisible on dark bg) → #f0b429 (amber, visible on both themes)
- [x] PM10 color: #cc0000 → #ff6b6b (brighter red, readable on dark)
- [x] Light/dark mode toggle button in web UI (persists via localStorage)

### v1.4.0
- [ ] Grafana dashboard JSON export for one-click import
- [ ] Alert threshold config in config.env (notify when AQI exceeds N)
- [ ] Historical data export endpoint (/api/export.csv)'''

if old_roadmap in content:
    content = content.replace(old_roadmap, new_roadmap)
elif '## Roadmap' in content:
    # Replace whatever roadmap section exists
    import re
    content = re.sub(r'## Roadmap.*$', new_roadmap, content, flags=re.DOTALL)

open('README.md', 'w').write(content)
print('OK: README roadmap updated')
PYEOF

# ── 4. Update CHANGELOG ───────────────────────────────────────────────────────
log "Updating CHANGELOG..."
python3 - << 'PYEOF'
import datetime
path = 'CHANGELOG.md'
content = open(path).read()
today = datetime.date.today().isoformat()
entry = f"""## [1.3.0-dev] - {today}
### Added
- Light/dark mode toggle button in web UI
  - Defaults to dark, toggles to light with sun/moon icon
  - Preference persisted in localStorage across page loads
  - Chart colors, grid, tick labels, legend all update on toggle

### Fixed
- AQI line color: was #181d27 (near-black, invisible on dark background)
  Changed to #f0b429 (amber) — visible on both dark and light themes
- PM10 line color: was #cc0000 (dark red, hard to read on dark background)
  Changed to #ff6b6b (bright red) — readable on both themes
- PM2.5 #42c0fb unchanged — already readable on dark

### Changed
- Chart dataset labels capitalised (aqi->AQI, pm10->PM10, pm2.5->PM2.5)
- Chart card now has border and background matching theme

"""
if '[1.3.0]' not in content and '[1.3.0-dev]' not in content:
    content = content.replace('# Changelog\n', f'# Changelog\n\n{entry}')
    open(path, 'w').write(content)
    print('OK: CHANGELOG updated')
else:
    print('OK: 1.3.0 entry already present')
PYEOF

# ── 5. Rebuild and restart ────────────────────────────────────────────────────
log "Rebuilding image..."
docker compose down 2>/dev/null || true
docker compose build

log "Starting paqm.service..."
sudo systemctl start paqm.service

log "Waiting for web container..."
for i in $(seq 1 24); do
    WEB=$(docker ps --filter "name=pi_air_quality_monitor_web" --format "{{.Names}}" 2>/dev/null || true)
    [[ -n "${WEB}" ]] && { ok "Container up: ${WEB}"; break; }
    sleep 5
done

log "Waiting for API..."
for i in $(seq 1 20); do
    curl -sf http://localhost:8000/api/ >/dev/null 2>&1 && { ok "API ready"; break; }
    sleep 3
done

# ── 6. Validate ───────────────────────────────────────────────────────────────
log "Validating..."
PASS=0; FAIL=0
chk() { [[ "$1" == "ok" ]] && { echo "  [PASS] $2"; ((++PASS)); } || { echo "  [FAIL] $2"; ((++FAIL)); }; }

PAGE=$(curl -sf http://localhost:8000/ 2>/dev/null || echo "")
echo "${PAGE}" | grep -q 'version: 1.3.0'    && chk ok "Template v1.3.0"       || chk fail "Template version wrong"
echo "${PAGE}" | grep -q 'toggleTheme'        && chk ok "toggleTheme present"   || chk fail "toggleTheme missing"
echo "${PAGE}" | grep -q 'f0b429'             && chk ok "AQI amber color"       || chk fail "AQI color not updated"
echo "${PAGE}" | grep -q 'ff6b6b'             && chk ok "PM10 bright red"       || chk fail "PM10 color not updated"
echo "${PAGE}" | grep -q 'data-theme'         && chk ok "Theme switching"       || chk fail "data-theme missing"
echo "${PAGE}" | grep -q 'localStorage'       && chk ok "Theme persistence"     || chk fail "localStorage missing"
curl -sf http://localhost:8000/api/ | python3 -c \
    "import json,sys; d=json.load(sys.stdin); assert d['historical']['aqi']['borderColor']=='#f0b429'" 2>/dev/null \
    && chk ok "API AQI color #f0b429" || chk fail "API AQI color not updated"
curl -sf http://localhost:8000/metrics | grep -q 'aqi_index' \
    && chk ok "/metrics endpoint" || chk fail "/metrics not responding"

echo
echo "  ${PASS} passed  ${FAIL} failed"
[[ "${FAIL}" -gt 0 ]] && { echo "  Fix failures before promoting."; exit 1; }

# ── 7. Commit and push ────────────────────────────────────────────────────────
log "Committing v1.3.0-dev..."
git add -A
git commit -m "feat(v1.3.0-dev): chart color fix + light/dark mode toggle

- AQI color: #181d27 (invisible on dark) -> #f0b429 (amber, readable always)
- PM10 color: #cc0000 (dark red) -> #ff6b6b (bright red, readable on dark)
- PM2.5 #42c0fb unchanged (already good)
- Light/dark toggle button (top-right header), defaults to dark
- Theme persisted in localStorage, chart colors update on toggle
- Dataset labels capitalised: AQI, PM10, PM2.5
- Chart card has themed border and background"

git push -u origin v1.3.0-dev
ok "Branch v1.3.0-dev pushed"

echo
echo "============================================================"
echo "  v1.3.0-dev deployed"
echo "  Web  : http://$(hostname -I | awk '{print $1}'):8000"
echo
echo "  Color changes:"
echo "    AQI  : #181d27 (black)    -> #f0b429 (amber)"
echo "    PM10 : #cc0000 (dark red) -> #ff6b6b (bright red)"
echo "    PM2.5: #42c0fb unchanged"
echo
echo "  New: Light/Dark toggle button top-right of header"
echo "       Preference saved in browser localStorage"
echo "============================================================"
