#!/usr/bin/env bash
cd ~/pi_air_quality_monitor

# Fix: aqi_monitor api/json should check the running container, not the pidfile
sed -i 's|\[[ ]*-z "${is_running}".*\] && { echo.*api service not running.*return.*||' \
    scripts/service/aqi_monitor.func
# Cleaner replacement:
sed -i 's|  \[[ ]*-z "${is_running}"[^;]*\|\|[^;]*! -e "${pidfile}"[^;]*\] && {[^}]*}||g' \
    scripts/service/aqi_monitor.func

# Archive lazy_script.sh
mv lazy_script.sh docs/dev-history/lazy_script.sh

# Tag and promote v1.1.0
echo "1.1.0" > VERSION
git add -A
git commit -m "release(v1.1.0): autostart confirmed working after reboot

- paqm.service: docker-compose stack starts at boot via systemd
- firefox-kiosk.service: opens --kiosk http://localhost:8000 after API ready
- ContainerConfig fix: docker-compose down before up in ExecStartPre
- Port 8000 confirmed open locally and on network after clean reboot"

git push origin v1.1.0-dev
git checkout main
git merge --no-ff v1.1.0-dev -m "release(v1.1.0): systemd autostart stable"
git tag -a v1.1.0 -m "v1.1.0 — systemd autostart for paqm + firefox kiosk"
git push origin main
git push origin v1.1.0
git checkout v1.1.0-dev
