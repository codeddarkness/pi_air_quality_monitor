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
cp config.env.example config.env   # edit for your system
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

Default Pi IP on this deployment: **<PI_IP_ADDRESS>**

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

Add an HTTP data source in Grafana pointing to `http://<PI_IP_ADDRESS>:8000/api/`
and use the JSON fields `historical.aqi.data`, `historical.pm10.data`,
`historical.pm2.data` with `historical.labels` as the time axis.

Grafana is running on this host at `http://<PI_IP_ADDRESS>:3000`.

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
@reboot ${PAQM_DIR}/scripts/service/aqi_monitor.func start 2>/dev/null
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


## Upstream / Credits

This project is a fork of [rydercalmdown/pi_air_quality_monitor](https://github.com/rydercalmdown/pi_air_quality_monitor).

The original work provides the Flask + Redis + Docker stack, SDS011 sensor
integration via `sds011lib`, Chart.js web interface, and APScheduler-based
data collection. All upstream code retains its original authorship.

**Changes in this fork** are documented in [CHANGELOG.md](CHANGELOG.md)
and [NOTICE](NOTICE).

---
## Known Issues / Roadmap (v1.1.0)

- [ ] Migrate `docker-compose` (v1.29.2) → `docker compose` (V2 plugin)
- [ ] Wire `systemd/paqm.service` for reliable boot ordering
- [ ] Wire `scripts/kiosk/start_firefox_kiosk.sh` to systemd for kiosk autostart
- [ ] Persist Redis data across clean restarts (currently lost on `docker-compose down`)
- [ ] Add Prometheus `/metrics` endpoint for native Grafana scraping
