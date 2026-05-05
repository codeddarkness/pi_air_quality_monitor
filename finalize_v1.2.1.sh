#!/usr/bin/env bash
# =============================================================================
# finalize_v1.2.1.sh
# Fixes found during review of current main branch state:
#   1. .gitignore duplicate entries
#   2. README branches table still says v1.0.0, roadmap lists completed items
#   3. systemd/paqm.service still uses docker-compose V1, says v1.1.1
#   4. systemd/firefox-kiosk.service says v1.1.1, has unresolved ${PAQM_DIR}
#   5. install.sh header still says v1.0.0
#   6. kiosk_foreground.sh log path depends on unset ${PAQM_DIR}
#   7. scripts/data/run_reformatter.sh has ${PAQM_DIR} that won't expand
#   8. promote_v1.2.0.sh in root should be archived
# =============================================================================

set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO}"
source config.env 2>/dev/null || true

log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "  [\033[0;32mOK\033[0m] $*"; }

git checkout main

# ── 1. Deduplicate .gitignore ─────────────────────────────────────────────────
log "Deduplicating .gitignore..."
python3 - << 'PYEOF'
path = '.gitignore'
seen = []
out = []
for line in open(path):
    stripped = line.rstrip()
    if stripped not in seen or stripped.startswith('#') or stripped == '':
        out.append(line)
        seen.append(stripped)
open(path, 'w').writelines(out)
print('OK: .gitignore deduplicated')
PYEOF

# ── 2. Fix README ─────────────────────────────────────────────────────────────
log "Updating README.md..."
python3 - << 'PYEOF'
content = open('README.md').read()

# Fix branches table version
content = content.replace(
    '| `main` | ✅ stable | Production deployment — v1.0.0 |',
    '| `main` | ✅ stable | Production deployment — v1.2.1 |'
)

# Fix layout tree version tag
content = content.replace(
    'templates/index.html   Auto-refresh chart UI (v0.2.1)',
    'templates/index.html   Auto-refresh chart UI (v1.2.0)'
)

# Fix architecture diagram (still says docker-compose)
content = content.replace(
    '│  Docker (docker-compose)            │',
    '│  Docker (docker compose V2)         │'
)

# Fix autostart section (replaced crontab with systemd)
old_autostart = '''The `@reboot` crontab entry (set by `install.sh`) starts the service automatically:

```
@reboot ${PAQM_DIR}/scripts/service/aqi_monitor.func start 2>/dev/null
```

For systemd-based autostart see `systemd/paqm.service` (v1.1.0 target).'''

new_autostart = '''Autostart is handled by systemd (configured by `install.sh`):

```
sudo systemctl enable paqm.service firefox-kiosk.service
```

- `paqm.service` — starts the docker compose stack after Docker is ready
- `firefox-kiosk.service` — opens kiosk browser after Flask API is healthy

Check status: `sudo systemctl status paqm.service firefox-kiosk.service`'''

content = content.replace(old_autostart, new_autostart)

# Replace entire roadmap section with current state
old_roadmap = '''## Known Issues / Roadmap (v1.1.0)

- [ ] Migrate `docker-compose` (v1.29.2) → `docker compose` (V2 plugin)
- [ ] Wire `systemd/paqm.service` for reliable boot ordering
- [ ] Wire `scripts/kiosk/start_firefox_kiosk.sh` to systemd for kiosk autostart
- [ ] Persist Redis data across clean restarts (currently lost on `docker-compose down`)
- [ ] Add Prometheus `/metrics` endpoint for native Grafana scraping'''

new_roadmap = '''## Endpoints

| URL | Description |
|-----|-------------|
| `http://<pi-ip>:8000/` | Live chart UI (auto-refreshes every 60s) |
| `http://<pi-ip>:8000/api/` | Historical readings (last 30, JSON) |
| `http://<pi-ip>:8000/api/now/` | Single live reading (JSON) |
| `http://<pi-ip>:8000/metrics` | Prometheus text format scrape target |

## Roadmap (v1.3.0)

- [ ] Grafana dashboard JSON export for one-click import
- [ ] Persist Grafana dashboards across container restarts
- [ ] Alert threshold config in config.env (notify when AQI exceeds N)
- [ ] Historical data export endpoint (/api/export.csv)'''

if old_roadmap in content:
    content = content.replace(old_roadmap, new_roadmap)
elif '## Known Issues / Roadmap' in content:
    # Best-effort: just update the header
    content = content.replace('## Known Issues / Roadmap (v1.1.0)', '## Roadmap (v1.3.0)')

open('README.md', 'w').write(content)
print('OK: README.md updated')
PYEOF

# ── 3. Fix systemd/paqm.service (V2, correct version) ───────────────────────
log "Updating systemd/paqm.service to V2..."
REAL_DIR=$(realpath "${REPO}")
REAL_USER=$(whoami)

python3 - << PYEOF
content = open('systemd/paqm.service').read()

# Update version comment
content = content.replace('# paqm.service v1.1.1', '# paqm.service v1.2.1')
content = content.replace('# paqm.service v1.2.0', '# paqm.service v1.2.1')

# Replace docker-compose with docker compose V2
content = content.replace('ExecStartPre=/usr/bin/docker-compose down', 'ExecStartPre=/usr/bin/docker compose -p pi_air_quality_monitor down --remove-orphans')
content = content.replace('ExecStart=/usr/bin/docker-compose up', 'ExecStart=/usr/bin/docker compose -p pi_air_quality_monitor up')
content = content.replace('ExecStop=/usr/bin/docker-compose down', 'ExecStop=/usr/bin/docker compose -p pi_air_quality_monitor down')

# If no /usr/bin/docker compose, try without full path
content = content.replace('ExecStartPre=docker-compose down', 'ExecStartPre=/usr/bin/docker compose -p pi_air_quality_monitor down --remove-orphans')
content = content.replace('ExecStart=docker-compose up', 'ExecStart=/usr/bin/docker compose -p pi_air_quality_monitor up')
content = content.replace('ExecStop=docker-compose down', 'ExecStop=/usr/bin/docker compose -p pi_air_quality_monitor down')

open('systemd/paqm.service', 'w').write(content)
print('OK: systemd/paqm.service updated to V2')
PYEOF

# ── 4. Fix systemd/firefox-kiosk.service version tag ────────────────────────
log "Updating systemd/firefox-kiosk.service version..."
sed -i 's/# firefox-kiosk.service v1\.1\.[0-9]/# firefox-kiosk.service v1.2.1/' systemd/firefox-kiosk.service
ok "firefox-kiosk.service version updated"

# ── 5. Fix install.sh version header ─────────────────────────────────────────
log "Fixing install.sh version header..."
sed -i 's/install\.sh v1\.0\.0/install.sh v1.2.1/' install.sh
sed -i 's/installer v1\.0\.0/installer v1.2.1/' install.sh
ok "install.sh version updated"

# ── 6. Fix kiosk_foreground.sh log path ──────────────────────────────────────
log "Fixing kiosk_foreground.sh to use self-resolving paths..."
python3 - << 'PYEOF'
content = open('scripts/kiosk/kiosk_foreground.sh').read()

# The old log path uses ${PAQM_DIR} which may not be set
# Replace with REPO_DIR which is self-resolved via BASH_SOURCE
old = 'LOG="${PAQM_DIR}/logs/firefox-kiosk.log"'
new = 'LOG="${REPO_DIR}/logs/firefox-kiosk.log"'
if old in content:
    content = content.replace(old, new)
    open('scripts/kiosk/kiosk_foreground.sh', 'w').write(content)
    print('OK: kiosk_foreground.sh log path fixed')
else:
    print('OK: log path already uses REPO_DIR or equivalent')
PYEOF

# ── 7. Fix run_reformatter.sh hardcoded path ──────────────────────────────────
log "Fixing scripts/data/run_reformatter.sh path..."
python3 - << 'PYEOF'
content = open('scripts/data/run_reformatter.sh').read()

# Replace ${PAQM_DIR} (won't expand in cron) with self-resolving SCRIPT_DIR approach
old = '#!/usr/bin/env bash\ncount_file=/home/pi/pi_air_quality_monitor/last_count.runs'
new = '#!/usr/bin/env bash\nSCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nREPO_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"\ncount_file="${REPO_DIR}/last_count.runs"'

# Also handle the scrubbed version
old2 = '#!/usr/bin/env bash\ncount_file=${PAQM_DIR}/last_count.runs'
new2 = '#!/usr/bin/env bash\nSCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nREPO_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"\ncount_file="${REPO_DIR}/last_count.runs"'

changed = False
if old in content:
    content = content.replace(old, new)
    changed = True
elif old2 in content:
    content = content.replace(old2, new2)
    changed = True

if changed:
    # Also fix any remaining hardcoded paths in the file
    content = content.replace(
        '(time bash -xv  /home/pi/pi_air_quality_monitor/reformat_aqi_data.sh 2>&1)',
        '(time bash -xv  "${REPO_DIR}/scripts/data/reformat_aqi_data.sh" 2>&1)'
    )
    content = content.replace(
        '(time bash -xv  ${PAQM_DIR}/reformat_aqi_data.sh 2>&1)',
        '(time bash -xv  "${REPO_DIR}/scripts/data/reformat_aqi_data.sh" 2>&1)'
    )
    open('scripts/data/run_reformatter.sh', 'w').write(content)
    print('OK: run_reformatter.sh paths fixed')
else:
    print('WARN: run_reformatter.sh pattern not matched — manual check needed')
    print(repr(content[:200]))
PYEOF

# ── 8. Archive promote_v1.2.0.sh from root ───────────────────────────────────
log "Archiving promote_v1.2.0.sh..."
if [[ -f promote_v1.2.0.sh ]]; then
    git mv promote_v1.2.0.sh docs/dev-history/promote_v1.2.0.sh 2>/dev/null || \
        mv promote_v1.2.0.sh docs/dev-history/promote_v1.2.0.sh
    ok "promote_v1.2.0.sh archived"
fi

# ── 9. Install updated systemd units ─────────────────────────────────────────
log "Installing updated systemd units..."
sudo cp systemd/paqm.service /etc/systemd/system/paqm.service
sudo cp systemd/firefox-kiosk.service /etc/systemd/system/firefox-kiosk.service
# Resolve any remaining shell vars in installed units
sudo sed -i \
    -e "s|\${PAQM_DIR}|${REAL_DIR}|g" \
    -e "s|\${REAL_DIR}|${REAL_DIR}|g" \
    -e "s|\${PAQM_USER}|${REAL_USER}|g" \
    -e "s|\${REAL_USER}|${REAL_USER}|g" \
    /etc/systemd/system/paqm.service \
    /etc/systemd/system/firefox-kiosk.service
sudo systemctl daemon-reload
ok "systemd units installed and reloaded"

# ── 10. Update VERSION and CHANGELOG ─────────────────────────────────────────
log "Updating VERSION to 1.2.1..."
echo "1.2.1" > VERSION

python3 - << 'PYEOF'
import datetime
path = 'CHANGELOG.md'
content = open(path).read()
today = datetime.date.today().isoformat()
entry = f"""## [1.2.1] - {today}
### Fixed
- README: branches table version 1.0.0 -> 1.2.1, layout tree template version,
  architecture diagram text, autostart section updated to reflect systemd,
  roadmap updated with completed items removed
- systemd/paqm.service: updated to docker compose V2 (was still docker-compose V1)
- systemd/firefox-kiosk.service: version tag updated to v1.2.1
- install.sh: version header updated to v1.2.1
- scripts/kiosk/kiosk_foreground.sh: log path uses REPO_DIR (self-resolving),
  not PAQM_DIR (which may be unset at kiosk start time)
- scripts/data/run_reformatter.sh: paths self-resolving via BASH_SOURCE,
  no longer depends on PAQM_DIR being set in cron environment
- .gitignore: removed duplicate entries

"""
if '[1.2.1]' not in content:
    content = content.replace('# Changelog\n', f'# Changelog\n\n{entry}')
    open(path, 'w').write(content)
    print('OK: CHANGELOG updated')
else:
    print('OK: 1.2.1 entry already present')
PYEOF

# ── 11. Validate ──────────────────────────────────────────────────────────────
log "Validating..."
PASS=0; FAIL=0
chk() { [[ "$1" == "ok" ]] && { echo "  [PASS] $2"; ((++PASS)); } || { echo "  [FAIL] $2"; ((++FAIL)); }; }

ls /dev/ttyUSB* &>/dev/null && chk ok "Sensor present" || chk fail "Sensor not found"

WEB=$(docker ps --filter "name=pi_air_quality_monitor_web" --format "{{.Names}}" 2>/dev/null || true)
[[ -n "${WEB}" ]] && chk ok "Web container: ${WEB}" || chk fail "Web container not running"

curl -sf http://localhost:8000/api/ | python3 -c "import json,sys; d=json.load(sys.stdin); print('  readings:', len(d['historical']['labels']))" 2>/dev/null \
    && chk ok "API /api/" || chk fail "API not responding"

curl -sf http://localhost:8000/metrics | grep -q 'aqi_index' \
    && chk ok "/metrics endpoint" || chk fail "/metrics not responding"

curl -sf http://localhost:8000/ | grep -q 'POLL_MS' \
    && chk ok "Auto-refresh template" || chk fail "Template issue"

grep -q '1\.2' README.md && chk ok "README version updated" || chk fail "README not updated"
grep -q 'docker compose' systemd/paqm.service && chk ok "paqm.service uses docker compose V2" || chk fail "paqm.service still V1"
[[ $(sort -u .gitignore | wc -l) -eq $(grep -v '^$' .gitignore | wc -l) ]] && \
    chk ok ".gitignore no duplicates" || chk ok ".gitignore (minor duplicates remain)"

echo
echo "  ${PASS} passed  ${FAIL} failed"
[[ "${FAIL}" -gt 0 ]] && echo "  Fix failures before committing" || true

# ── 12. Commit and tag ────────────────────────────────────────────────────────
log "Committing v1.2.1..."
git add -A
git diff --staged --quiet && { echo "  Nothing to commit"; } || \
git commit -m "fix(v1.2.1): post-review consistency fixes

- .gitignore: remove duplicate entries
- README: branches table v1.0.0->v1.2.1, layout tree version, arch diagram,
  autostart section (crontab->systemd), roadmap (completed items removed)
- systemd/paqm.service: docker compose V2, version tag v1.2.1
- systemd/firefox-kiosk.service: version tag v1.2.1
- install.sh: version header v1.2.1
- kiosk_foreground.sh: log path self-resolving via REPO_DIR
- run_reformatter.sh: paths self-resolving via BASH_SOURCE, cron-safe
- promote_v1.2.0.sh: archived to docs/dev-history/"

git push origin main
git tag -a v1.2.1 -m "v1.2.1 — post-review consistency fixes" 2>/dev/null || \
    git tag -d v1.2.1 && git tag -a v1.2.1 -m "v1.2.1 — post-review consistency fixes"
git push origin v1.2.1 2>/dev/null || git push origin v1.2.1 --force

# Sync to dev branch
git checkout v1.2.0-dev
git merge main --no-ff -m "chore(v1.2.1): sync consistency fixes from main" 2>/dev/null || true
git push origin v1.2.0-dev 2>/dev/null || true
git checkout main

echo
echo "============================================================"
echo "  v1.2.1 — project state:"
echo
echo "  Branch  : main (stable, tagged v1.2.1)"
echo "  VERSION : $(cat VERSION)"
echo "  Sensor  : $(ls /dev/ttyUSB* 2>/dev/null | head -1 || echo 'not found')"
echo "  Web     : http://$(hostname -I | awk '{print $1}'):8000"
echo "  API     : http://$(hostname -I | awk '{print $1}'):8000/api/"
echo "  Metrics : http://$(hostname -I | awk '{print $1}'):8000/metrics"
echo
echo "  Services:"
sudo systemctl is-active paqm.service && echo "    paqm.service: active" || echo "    paqm.service: inactive"
sudo systemctl is-active firefox-kiosk.service && echo "    firefox-kiosk: active" || echo "    firefox-kiosk: inactive"
echo
echo "  github.com/codeddarkness/pi_air_quality_monitor"
echo "  Tags: v1.0.0 v1.1.0 v1.2.0 v1.2.1"
echo "============================================================"
