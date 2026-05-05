# Changelog

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
