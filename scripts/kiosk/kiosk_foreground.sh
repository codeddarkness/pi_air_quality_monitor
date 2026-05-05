#!/usr/bin/env bash
# kiosk_foreground.sh v1.1.1
# Runs firefox-esr in kiosk mode, stays in foreground for systemd.
# Polls API before starting so we don't get a blank page.

DISPLAY="${DISPLAY:-:0}"
export DISPLAY
export XAUTHORITY="${XAUTHORITY:-/home/pi/.Xauthority}"
URL="http://localhost:8000"
LOG="/home/pi/pi_air_quality_monitor/logs/firefox-kiosk.log"

mkdir -p "$(dirname "${LOG}")"

ts() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*" | tee -a "${LOG}"; }

ts "Kiosk starting — waiting for API at ${URL}/api/"
for i in $(seq 1 40); do
    curl -sf "${URL}/api/" >/dev/null 2>&1 && { ts "API ready after ${i} attempts"; break; }
    ts "Attempt ${i}/40 — sleeping 5s"
    sleep 5
done

ts "Launching firefox-esr --kiosk ${URL}"
exec firefox-esr --kiosk "${URL}" 2>>"${LOG}"
