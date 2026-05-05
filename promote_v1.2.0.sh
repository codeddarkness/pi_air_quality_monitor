#!/usr/bin/env bash
# promote_v1.2.0.sh
# - Fix truncated index.html template
# - Clean dev/patch scripts from repo root
# - Update CHANGELOG and README
# - Promote v1.2.0-dev to main, tag v1.2.0

set -euo pipefail
REPO="${HOME}/pi_air_quality_monitor"
cd "${REPO}"
source config.env 2>/dev/null || true

log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "  [\033[0;32mOK\033[0m] $*"; }

git checkout v1.2.0-dev

# ── 1. Fix template ───────────────────────────────────────────────────────────
log "Writing complete index.html v1.2.0..."
mkdir -p src/templates
python3 - << 'PYEOF'
template = '''<!doctype html>
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

fetchAndUpdate();
setInterval(fetchAndUpdate, POLL_MS);
</script>
</body>
</html>'''

with open('src/templates/index.html', 'w') as f:
    f.write(template)
print('OK: index.html written via python (no heredoc truncation risk)')
PYEOF
ok "index.html written"

# Verify key sections present
python3 -c "
t = open('src/templates/index.html').read()
checks = ['version: 1.2.0', 'POLL_MS', 'buildDatasets', 'data.historical.aqi', 'data.historical.pm10', 'data.historical.pm2', 'setInterval', 'fetchAndUpdate']
for c in checks:
    assert c in t, f'MISSING: {c}'
print('  Template verified: all sections present')
"

# ── 2. Rebuild with fixed template ────────────────────────────────────────────
log "Rebuilding image with fixed template..."
docker compose down 2>/dev/null || true
docker compose build
sudo systemctl start paqm.service
sleep 20
source scripts/service/aqi_monitor.func
aqi_monitor status

# Quick template verify via curl
TMPL=$(curl -sf http://localhost:8000/ 2>/dev/null || echo "")
if echo "${TMPL}" | grep -q 'POLL_MS' && echo "${TMPL}" | grep -q 'buildDatasets'; then
    ok "Template serving correctly (POLL_MS + buildDatasets confirmed)"
else
    echo "  WARNING: template check failed — inspect: curl http://localhost:8000/"
fi

# ── 3. Clean dev/patch scripts from repo ─────────────────────────────────────
log "Archiving dev scripts to docs/dev-history/..."
for f in setup_v1.1.0.sh setup_v1.2.0.sh patch_systemd_services.sh \
          cleanup_and_update_readme.sh close_out.sh; do
    if [[ -f "${f}" ]] && ! git ls-files --error-unmatch "docs/dev-history/${f}" 2>/dev/null; then
        git mv "${f}" "docs/dev-history/${f}" 2>/dev/null || mv "${f}" "docs/dev-history/${f}"
        ok "Archived: ${f}"
    fi
done

# Remove runtime artifacts from tracking
for f in last_count.runs firefox-esr-run.log lazy.sh; do
    git rm --cached "${f}" 2>/dev/null && ok "Untracked: ${f}" || true
done

# Add to gitignore
for pattern in 'last_count.runs' 'firefox-esr-run.log' 'lazy*.sh'; do
    grep -q "^${pattern}$" .gitignore || echo "${pattern}" >> .gitignore
done
ok ".gitignore updated"

# ── 4. Update CHANGELOG ───────────────────────────────────────────────────────
log "Updating CHANGELOG..."
python3 - << 'PYEOF'
import re
path = 'CHANGELOG.md'
content = open(path).read()

entry = """## [1.2.0] - 2026-05-05
### Added
- config.env.example: deployment configuration template (committed)
  config.env: local overrides (gitignored, auto-generated by install.sh)
- /metrics endpoint: Prometheus text format (aqi_index, pm10_ugm3, pm25_ugm3)
- docker compose V2: no version key, native plugin, no ContainerConfig crashes
- Redis named volume (redis_data): data persists across restarts
- Redis appendonly persistence + save intervals
- install.sh: generates config.env, installs compose V2 plugin

### Fixed
- All hardcoded IPs/hostnames/paths removed from tracked files
- Container timezone: /etc/localtime + /etc/timezone mounted read-only
  (timestamps now match system local time, not UTC)
- index.html: dark theme + 60s auto-refresh restored after branch cut regression
- aqi_monitor.func: pushd instead of cd (no longer clobbers caller CWD)
- docker compose V2 in aqi_monitor.func and paqm.service

### Changed
- Makefile: config.env aware, TARGET_HOST for copy/shell targets
- Dev/patch scripts archived to docs/dev-history/
- Runtime artifacts (last_count.runs, firefox-esr-run.log) gitignored

"""

# Replace dev entry or insert after # Changelog
if '[1.2.0]' not in content:
    content = content.replace('# Changelog\n', f'# Changelog\n\n{entry}')
    open(path, 'w').write(content)
    print('OK: CHANGELOG updated')
else:
    print('OK: [1.2.0] entry already present')
PYEOF

# ── 5. Update README version table ────────────────────────────────────────────
log "Updating README version table..."
python3 - << 'PYEOF'
path = 'README.md'
content = open(path).read()

new_row = '| `1.2.0` | 2026-05-05 | Config system, compose V2, /metrics, no PII, timezone fix |\n'
if '1.2.0' not in content:
    content = content.replace(
        '| `1.1.0`',
        f'{new_row}| `1.1.0`'
    )
    # Also update deploy instructions to show config.env step
    content = content.replace(
        'bash install.sh\n```',
        'cp config.env.example config.env   # edit for your system\nbash install.sh\n```'
    )
    open(path, 'w').write(content)
    print('OK: README updated')
else:
    print('OK: README already has 1.2.0')
PYEOF

# ── 6. Final validation ───────────────────────────────────────────────────────
log "Running validation..."
PASS=0; FAIL=0
chk() { [[ "$1" == "ok" ]] && { echo "  [PASS] $2"; ((++PASS)); } || { echo "  [FAIL] $2"; ((++FAIL)); }; }

ls /dev/ttyUSB* &>/dev/null && chk ok "Sensor /dev/ttyUSB0" || chk fail "Sensor not found"

WEB=$(docker ps --filter "name=pi_air_quality_monitor_web" --format "{{.Names}}" 2>/dev/null || true)
[[ -n "${WEB}" ]] && chk ok "Web container: ${WEB}" || chk fail "Web container not running"

API=$(curl -sf http://localhost:8000/api/ 2>/dev/null || echo "")
echo "${API}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert len(d['historical']['labels'])>0" 2>/dev/null \
    && chk ok "API responding" || chk fail "API not responding"

curl -sf http://localhost:8000/metrics | grep -q 'aqi_index' \
    && chk ok "/metrics endpoint" || chk fail "/metrics not responding"

TMPL=$(curl -sf http://localhost:8000/ 2>/dev/null || echo "")
echo "${TMPL}" | grep -q 'POLL_MS' && chk ok "Auto-refresh template" || chk fail "Template missing POLL_MS"
echo "${TMPL}" | grep -q 'version: 1.2.0' && chk ok "Template version 1.2.0" || chk fail "Version tag missing"

[[ -f config.env.example ]] && chk ok "config.env.example committed" || chk fail "config.env.example missing"
grep -q '^config\.env$' .gitignore && chk ok "config.env gitignored" || chk fail "config.env not gitignored"

echo
echo "Validation: ${PASS} passed  ${FAIL} failed"
[[ "${FAIL}" -gt 0 ]] && { echo "Fix failures before promoting."; exit 1; }

# ── 7. Commit + promote ───────────────────────────────────────────────────────
log "Committing v1.2.0..."
echo "1.2.0" > VERSION
git add -A
git commit -m "release(v1.2.0): stable — template fix, timezone, cleanup

- index.html: fix truncated template (written via python, not heredoc)
- Container timezone: /etc/localtime mounted, timestamps match local time
- Dev scripts archived to docs/dev-history/
- Runtime artifacts gitignored
- CHANGELOG and README updated for v1.2.0"

git push origin v1.2.0-dev

log "Merging to main..."
git checkout main
git merge --no-ff v1.2.0-dev -m "release(v1.2.0): config system, compose V2, /metrics, no PII"
git tag -a v1.2.0 -m "v1.2.0 — Prometheus metrics, docker compose V2, config.env, timezone fix"
git push origin main
git push origin v1.2.0
git checkout v1.2.0-dev

echo
echo "============================================================"
echo "  v1.2.0 released"
echo "  main: stable, tagged v1.2.0"
echo "  Web    : http://$(hostname -I | awk '{print $1}'):8000"
echo "  API    : http://$(hostname -I | awk '{print $1}'):8000/api/"
echo "  Metrics: http://$(hostname -I | awk '{print $1}'):8000/metrics"
echo
echo "  Note: UTC timestamps will age out of the 30-reading window"
echo "  within 30 minutes as new local-time readings replace them."
echo
echo "  Fresh deploy on any Pi:"
echo "    git clone git@github.com:codeddarkness/pi_air_quality_monitor.git"
echo "    cd pi_air_quality_monitor"
echo "    cp config.env.example config.env"
echo "    bash install.sh"
echo "============================================================"
