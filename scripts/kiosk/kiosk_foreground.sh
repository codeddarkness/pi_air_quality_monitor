#!/usr/bin/env bash
# kiosk_foreground.sh v1.3.0
# Waits for X display and API, then opens Firefox in kiosk mode.
# --no-remote forces a fresh instance even if Firefox is already open.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"
[[ -f "${REPO_DIR}/config.env" ]] && source "${REPO_DIR}/config.env"

DISPLAY="${KIOSK_DISPLAY:-:0}"
URL="${KIOSK_URL:-http://localhost:${PAQM_PORT:-8000}}"
LOG="${REPO_DIR}/logs/firefox-kiosk.log"
PROFILE_DIR="/tmp/paqm-kiosk-profile"

export DISPLAY
export XAUTHORITY="${XAUTHORITY:-/home/${PAQM_USER:-pi}/.Xauthority}"

mkdir -p "$(dirname "${LOG}")" "${PROFILE_DIR}"
ts() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*" | tee -a "${LOG}"; }

ts "kiosk_foreground.sh v1.3.0 starting"
ts "URL=${URL} DISPLAY=${DISPLAY}"

# Wait for X display to be ready (up to 60s)
ts "Waiting for X display ${DISPLAY}..."
for i in $(seq 1 30); do
    xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1 && { ts "Display ready (attempt ${i})"; break; }
    [[ "${i}" -eq 30 ]] && { ts "ERROR: display ${DISPLAY} not available after 60s"; exit 1; }
    sleep 2
done

# Kill any existing Firefox kiosk profile to prevent lock issues
rm -f "${PROFILE_DIR}/lock" "${PROFILE_DIR}/.parentlock" 2>/dev/null

# Wait for Flask API (up to 3 min)
ts "Waiting for API at ${URL}/api/..."
for i in $(seq 1 36); do
    curl -sf "${URL}/api/" >/dev/null 2>&1 && { ts "API ready (attempt ${i})"; break; }
    [[ "${i}" -eq 36 ]] && ts "WARNING: API not ready after 3min, opening anyway"
    sleep 5
done

ts "Launching firefox-esr --kiosk --no-remote"
exec firefox-esr \
    --kiosk \
    --no-remote \
    --profile "${PROFILE_DIR}" \
    "${URL}" 2>>"${LOG}"
