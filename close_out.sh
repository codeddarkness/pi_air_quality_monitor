#!/usr/bin/env bash
cd ~/pi_air_quality_monitor

# Fix the pidfile check in aqi_monitor api|json case
# Replace: checks pidfile AND is_running
# With: checks is_running only (pidfile doesn't exist when started by systemd)
sed -i 's/\[[ ]*-z "${is_running}"[^;]*||[^;]*! -e "${pidfile}"[^;]*\]/[ -z "${is_running}" ]/' \
    scripts/service/aqi_monitor.func

# Verify the fix looks right
grep -A2 'api|json' scripts/service/aqi_monitor.func

# Archive lazy_script.sh, update VERSION
mv lazy_script.sh docs/dev-history/ 2>/dev/null || true
echo "1.1.0" > VERSION

# Update CHANGELOG
sed -i '0,/\[1\.1\.0-dev\]/s/\[1\.1\.0-dev\]/[1.1.0]/' CHANGELOG.md

git add -A
git commit -m "release(v1.1.0): autostart confirmed + fix aqi_monitor api pidfile check

- aqi_monitor api/json: check is_running only, not pidfile
  (pidfile absent when service started by systemd, not aqi_monitor start)
- Autostart confirmed: paqm.service + firefox-kiosk.service survive reboot
- Port 8000 open, API responding, Firefox loading kiosk at boot"

git push origin v1.1.0-dev

# Promote to main
git checkout main
git merge --no-ff v1.1.0-dev -m "release(v1.1.0): systemd autostart stable"
git tag -a v1.1.0 -m "v1.1.0 — systemd autostart paqm + firefox kiosk, confirmed on reboot"
git push origin main
git push origin v1.1.0
git checkout v1.1.0-dev
echo "Done — v1.1.0 tagged on main"
