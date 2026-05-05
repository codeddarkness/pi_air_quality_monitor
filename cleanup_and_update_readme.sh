#!/usr/bin/env bash
# =============================================================================
# cleanup_and_update_readme.sh v1.0.1
# - Archive one-time patch scripts to docs/dev-history/
# - Write updated README.md with versioning, branches, and status
# - Commit to main, sync to custom_dev
# =============================================================================

set -euo pipefail
REPO="${HOME}/pi_air_quality_monitor"
cd "${REPO}"

log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "  [\033[0;32mOK\033[0m] $*"; }

# Ensure we're on main
CURRENT=$(git branch --show-current)
[[ "${CURRENT}" == "main" ]] || { log "Switching to main..."; git checkout main; }

# ── 1. Stage and commit the .gitignore change that's been floating ────────────
log "Committing pending .gitignore update..."
git add .gitignore
git diff --staged --quiet || git commit -m "chore: add *.bak.* to .gitignore"

# ── 2. Archive one-time patch scripts → docs/dev-history/ ────────────────────
log "Archiving patch scripts..."
mkdir -p docs/dev-history

for f in setup_dev_branch.sh apply_live_refresh.sh fix_sensor_and_paths.sh validate_and_promote.sh; do
    if [[ -f "${f}" ]]; then
        git mv "${f}" "docs/dev-history/${f}"
        ok "Archived: ${f} → docs/dev-history/"
    fi
done

# last_count.runs is a runtime artifact, not source — add to gitignore
grep -q 'last_count.runs' .gitignore || echo 'last_count.runs' >> .gitignore
git rm --cached last_count.runs 2>/dev/null || true
ok "last_count.runs removed from tracking"

# ── 3. Update Makefile to reflect new script locations ───────────────────────
log "Updating Makefile..."
cat > Makefile << 'MAKEEOF'
# pi_air_quality_monitor Makefile v1.0.1
PI_IP_ADDRESS=10.0.0.194
PI_USERNAME=pi

.PHONY: run stop restart status build install validate copy shell log api

run:
	@source scripts/service/aqi_monitor.func && aqi_monitor start

stop:
	@source scripts/service/aqi_monitor.func && aqi_monitor stop

restart:
	@source scripts/service/aqi_monitor.func && aqi_monitor restart

status:
	@source scripts/service/aqi_monitor.func && aqi_monitor status

build:
	@docker-compose build

install:
	@bash install.sh

validate:
	@bash -c 'REPO=$(pwd); \
	  echo "Sensor:"; ls /dev/ttyUSB* 2>/dev/null || echo "  not found"; \
	  echo "Containers:"; docker ps --filter name=pi_air_quality_monitor --format "  {{.Names}} {{.Status}}"; \
	  echo "API:"; curl -sf http://localhost:8000/api/ | python3 -c \
	    "import json,sys; d=json.load(sys.stdin); \
	     print(\"  readings:\", len(d[\"historical\"][\"labels\"]), \
	           \"| latest:\", d[\"historical\"][\"labels\"][-1], \
	           \"| AQI:\", d[\"historical\"][\"aqi\"][\"data\"][-1])" 2>/dev/null || echo "  API not responding"'

copy:
	@rsync -av $(shell pwd)/ --exclude .git --exclude data/redis --exclude logs \
	  --exclude _local_data --exclude json_data --exclude '*.pyc' \
	  $(PI_USERNAME)@$(PI_IP_ADDRESS):/home/$(PI_USERNAME)/pi_air_quality_monitor/

shell:
	@ssh $(PI_USERNAME)@$(PI_IP_ADDRESS)

log:
	@tail -f /tmp/sensor_logs/aqi_monitor.log

api:
	@curl -s http://$(PI_IP_ADDRESS):8000/api/ | python3 -m json.tool 2>/dev/null \
	  || curl -s http://$(PI_IP_ADDRESS):8000/api/
MAKEEOF
ok "Makefile updated"

# ── 4. Write new README.md ────────────────────────────────────────────────────
log "Writing README.md..."
cat > README.md << 'READMEEOF'
# Raspberry Pi Air Quality Monitor

Real-time air quality monitoring using a SDS011 particulate matter sensor,
served via Flask + Redis + Docker with an auto-refreshing web interface.

[![Version](https://img.shields.io/badge/version-1.0.0-blue)](CHANGELOG.md)
[![Branch](https://img.shields.io/badge/branch-main%20%7C%20custom__dev-green)](./)

---

## Branches

| Branch | Status | Description |
|--------|--------|-------------|
| `main` | ✅ stable | Production deployment — v1.0.0 |
| `custom_dev` | 🔧 active dev | Feature development and fixes |

---

## Hardware

- Raspberry Pi (tested on Pi OS Bookworm / Debian 12)
- [SDS011 Nova PM Sensor](http://inovafitness.com/en/a/chanpinzhongxin/95.html) via USB (CH340 converter)
- USB → `/dev/ttyUSB0` → Docker device passthrough

---

## Quick Start

```bash
git clone git@github.com:codeddarkness/pi_air_quality_monitor.git
cd pi_air_quality_monitor
bash install.sh
```

`install.sh` handles: system packages, Docker, docker-compose, udev rule,
`.bashrc` sourcing, crontab `@reboot` entry, image build, and first start.

---

## Managing the Service

```bash
aqi_monitor start    # start Docker stack (20s sensor warmup)
aqi_monitor stop     # stop Docker stack
aqi_monitor restart  # stop + start
aqi_monitor status   # sensor + container status
aqi_monitor api      # print latest JSON from /api/
aqi_monitor log      # tail -F the docker-compose log
```

Or via Make:

```bash
make run       # start
make stop      # stop
make status    # sensor + container status
make validate  # readings + API check
make log       # tail log
make api       # curl /api/ with JSON formatting
```

---

## Endpoints

| URL | Description |
|-----|-------------|
| `http://<pi-ip>:8000/` | Live chart UI (auto-refreshes every 60s) |
| `http://<pi-ip>:8000/api/` | Historical readings (last 30, JSON) |
| `http://<pi-ip>:8000/api/now/` | Single live reading (JSON) |

Default Pi IP on this deployment: **10.0.0.194**

---

## API Response Format

```json
{
  "historical": {
    "labels": ["2026-05-05 21:02:51", "..."],
    "aqi":  { "label": "aqi",   "data": [1.0, 2.0, ...], "borderColor": "#181d27" },
    "pm10": { "label": "pm10",  "data": [0.5, 1.2, ...], "borderColor": "#cc0000" },
    "pm2":  { "label": "pm2.5", "data": [0.2, 0.4, ...], "borderColor": "#42C0FB" }
  }
}
```

**AQI note:** Values of 1–2 indicate very clean air (PM2.5 < 1 µg/m³).
EPA threshold for "Good" is AQI ≤ 50 (PM2.5 ≤ 12 µg/m³).

---

## Grafana Integration

Add an HTTP data source in Grafana pointing to `http://10.0.0.194:8000/api/`
and use the JSON fields `historical.aqi.data`, `historical.pm10.data`,
`historical.pm2.data` with `historical.labels` as the time axis.

Grafana is running on this host at `http://10.0.0.194:3000`.

---

## Architecture

```
SDS011 Sensor
    │ /dev/ttyUSB0
    ▼
┌─────────────────────────────────────┐
│  Docker (docker-compose)            │
│  ┌─────────────┐  ┌──────────────┐ │
│  │ web          │  │ redis        │ │
│  │ Flask :8000  │◄─│ :6379        │ │
│  │ APScheduler  │  │ persists RDB │ │
│  └─────────────┘  └──────────────┘ │
└─────────────────────────────────────┘
    │ :8000
    ▼
Browser (auto-refresh every 60s)
Grafana (HTTP data source)
```

---

## Project Layout

```
pi_air_quality_monitor/
├── src/
│   ├── app.py                  Flask app + API routes
│   ├── AirQualityMonitor.py    SDS011 sensor + Redis interface
│   ├── requirements.txt
│   └── templates/index.html   Auto-refresh chart UI (v0.2.1)
├── scripts/
│   ├── service/
│   │   ├── aqi_monitor.func   Shell functions: start/stop/status/api
│   │   ├── set_tty_aqi.sh     udev rule setup for CH340 sensor
│   │   └── paqm.service       systemd unit (optional, see systemd/)
│   ├── data/
│   │   ├── reformat_aqi_data.sh  Reformat Redis data → JSON file
│   │   ├── run_reformatter.sh    Cron wrapper for reformat
│   │   └── check_ranges.func     Data range analysis utilities
│   └── kiosk/
│       └── start_firefox_kiosk.sh  Firefox ESR kiosk mode (display :0)
├── systemd/
│   └── paqm.service            systemd unit for autostart
├── docs/
│   ├── dev-history/            One-time patch scripts (archived)
│   └── diagnostics/            Deployment logs from initial setup
├── docker-compose.yaml         Production compose config
├── docker-compose.custom.yaml  Alternate with timezone mounts
├── Dockerfile
├── install.sh                  Fresh deployment installer
├── Makefile                    Dev shortcuts
├── aqi_monitor.func            Symlink → scripts/service/aqi_monitor.func
├── VERSION                     1.0.0
└── CHANGELOG.md
```

---

## Autostart on Boot

The `@reboot` crontab entry (set by `install.sh`) starts the service automatically:

```
@reboot /home/pi/pi_air_quality_monitor/scripts/service/aqi_monitor.func start 2>/dev/null
```

For systemd-based autostart see `systemd/paqm.service` (v1.1.0 target).

---

## Versioning

This project uses [Semantic Versioning](https://semver.org/):

| Version | Date | Notes |
|---------|------|-------|
| `1.0.0` | 2026-05-05 | Stable — auto-refresh UI, sensor fix, install.sh |
| `0.2.2` | 2026-05-05 | Fix sensor detection, path migration |
| `0.2.1` | 2026-05-05 | Auto-refresh chart, log redirect fix |
| `0.2.0` | 2026-05-05 | Dev branch init, script reorganisation |
| `0.1.0` | 2026-05-05 | Initial mirror |

See [CHANGELOG.md](CHANGELOG.md) for full history.

---

## Known Issues / Roadmap (v1.1.0)

- [ ] Migrate `docker-compose` (v1.29.2) → `docker compose` (V2 plugin)
- [ ] Wire `systemd/paqm.service` for reliable boot ordering
- [ ] Wire `scripts/kiosk/start_firefox_kiosk.sh` to systemd for kiosk autostart
- [ ] Persist Redis data across clean restarts (currently lost on `docker-compose down`)
- [ ] Add Prometheus `/metrics` endpoint for native Grafana scraping
READMEEOF
ok "README.md written"

# ── 5. Commit and push main ───────────────────────────────────────────────────
log "Committing to main..."
git add -A
git commit -m "chore(v1.0.1): cleanup patch scripts, update README and Makefile

- Archive one-time patch scripts → docs/dev-history/
- Remove last_count.runs from tracking (runtime artifact)
- README.md: full rewrite with branches, API docs, architecture,
  versioning table, layout, Grafana integration, roadmap
- Makefile: updated targets (run/stop/restart/status/validate/log/api)
  with corrected PI_IP_ADDRESS and new script paths"

log "Pushing main..."
git push origin main

# ── 6. Sync cleanup to custom_dev ────────────────────────────────────────────
log "Syncing cleanup to custom_dev..."
git checkout custom_dev
git merge main --no-ff -m "chore(v1.0.1): sync cleanup from main

- Archived patch scripts, updated README and Makefile"
git push origin custom_dev
git checkout main

echo
echo "══════════════════════════════════════════════════════════════"
echo "  v1.0.1 — cleanup complete"
echo
echo "  main       : stable, tagged v1.0.0, cleaned up"
echo "  custom_dev : synced with main cleanup"
echo
echo "  Archived to docs/dev-history/:"
echo "    setup_dev_branch.sh"
echo "    apply_live_refresh.sh"
echo "    fix_sensor_and_paths.sh"
echo "    validate_and_promote.sh"
echo
echo "  github.com/codeddarkness/pi_air_quality_monitor"
echo "══════════════════════════════════════════════════════════════"
