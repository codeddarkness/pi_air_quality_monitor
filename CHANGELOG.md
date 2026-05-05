# Changelog

## [1.1.0] - 2026-05-05
### Added
- NOTICE file with upstream attribution to rydercalmdown/pi_air_quality_monitor
- README: upstream credit section with link to original project
- systemd/paqm.service: docker-compose stack with After=docker.service
- systemd/firefox-kiosk.service: kiosk After=paqm.service with API health check
- ExecStartPre health check loop: waits up to 90s for Flask API before opening browser

### Fixed
- Boot autostart: replaced racy @reboot crontab with ordered systemd units
  (crontab fires before Docker daemon ready; systemd Requires= prevents this)
- firefox-kiosk: was opening localhost:8000 before Flask was serving requests

### Changed
- @reboot crontab entries commented out (paqm.service takes over)


## [1.0.0] - 2026-05-05
### Fixed
- sensor_online(): direct /dev/ttyUSBx check instead of dmesg-only
- aqi_monitor.func log redirect (double > redirect silenced all output)
- Path migration: custom/ → scripts/{kiosk,data,service}/
- Crontab and .bashrc updated to new script paths
- Backward-compat symlink at repo root for aqi_monitor.func

### Added
- Auto-refresh chart (60s polling, no page reload) — index.html v0.2.1
- Dark theme UI with live status indicator
- install.sh for fresh deployments
- VERSION and CHANGELOG.md with semantic versioning
- docs/diagnostics/ for deployment logs

### Architecture
- Flask + Redis + docker-compose stack unchanged
- SDS011 sensor via /dev/ttyUSB0 → docker device passthrough
- API: /api/ (historical), /api/now/ (live), /  (chart UI)
- Grafana compatible via HTTP data source at :8000/api/


## [Unreleased] - 0.2.0-dev
### Added
- `custom_dev` branch for structured re-implementation
- `scripts/kiosk/` — Firefox ESR kiosk scripts (migrated from custom/)
- `scripts/data/` — data collection, reformat, and API scripts
- `scripts/service/` — install, aqi_monitor.func, crontab
- `systemd/` — unit files for review and deployment
- `docs/diagnostics/` — make_install.log, make_run.log, docker_ps.txt

### Known Issues (to fix)
- docker-compose v1.29.2 ContainerConfig KeyError → migrate to `docker compose` (V2 plugin)
- Data refresh stale in browser → reformat_aqi_data.sh cron reliability
- Kiosk start order race (Firefox before docker stack is ready)
- Redis data not persisted across restarts on clean run

## [0.1.0] - initial mirror
### Added
- Mirror of rydercalmdown/pi_air_quality_monitor
- custom/ directory with previous deployment scripts
