#!/usr/bin/env bash
# =============================================================================
# Fix Firefox Kiosk Permissions
# Resolves permission issues with the Firefox kiosk script
# =============================================================================

set -e

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo or as root"
   exit 1
fi

echo "Fixing Firefox Kiosk Permissions"
echo "=============================="

# Update script to use a log file in the home directory
SCRIPT_PATH="${PAQM_DIR}/start_firefox_kiosk.sh"
SCRIPT_BACKUP="${SCRIPT_PATH}.bak.$(date +%Y%m%d%H%M%S)"

# Backup the current script
cp "${SCRIPT_PATH}" "${SCRIPT_BACKUP}"
echo "Created backup at: ${SCRIPT_BACKUP}"

# Create logs directory if it doesn't exist
mkdir -p ${PAQM_DIR}/logs
chown -R pi:pi ${PAQM_DIR}/logs

# Update the script
echo "Updating kiosk script to use proper log path..."
cat > "${SCRIPT_PATH}" << 'EOF'
#!/usr/bin/env bash
# =============================================================================
# Firefox Kiosk Mode Script for Raspberry Pi Air Quality Monitor
# Launches Firefox in fullscreen mode and maintains the session
# =============================================================================

# Configuration
KIOSK_URL="localhost:8000"
REFRESH_INTERVAL=60
LOG_DIR="${PAQM_DIR}/logs"
LOG_FILE="${LOG_DIR}/firefox-kiosk.log"
DISPLAY=":0"

export DISPLAY

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function with timestamp
log_message() {
    local timestamp
    timestamp=$(date "+%Y-%m-%dT%H:%M:%S %Z")
    echo -e "[ ${timestamp} ] : $*" | tee -a "${LOG_FILE}"
}

# Function to stop Firefox and related processes
stop_firefox() {
    log_message "Stopping Firefox and related processes..."
    
    # Terminate background processes
    for pid in "${FIREFOX_PID}" "${FULLSCREEN_PID}" "${REFRESH_PID}"; do
        if [[ -n "${pid}" ]]; then
            kill "${pid}" 2>/dev/null || true
        fi
    done
    
    # Ensure Firefox is completely closed
    killall firefox-esr 2>/dev/null || true
    
    # Find and kill any instances of this script (except current)
    mapfile -t SCRIPT_PIDS < <(ps -ef | grep "$(basename "$0")" | grep -v grep | grep -v "$$" | awk '{print $2}')
    for pid in "${SCRIPT_PIDS[@]}"; do
        kill "${pid}" 2>/dev/null && log_message "Killed script process ${pid}"
    done
    
    # Final cleanup for any remaining Firefox processes
    mapfile -t REMAINING_PIDS < <(ps -ef | grep 'start_firefox_kiosk.sh\|firefox-esr' | grep -v 'log\|grep' | awk '{print $2}')
    for pid in "${REMAINING_PIDS[@]}"; do
        if [[ -n "${pid}" ]]; then
            kill "${pid}" 2>/dev/null && log_message "Killed remaining process ${pid}"
        fi
    done
    
    log_message "All Firefox processes stopped"
    return 0
}

# Function to start Firefox in kiosk mode
start_firefox() {
    log_message "Starting Firefox ESR in kiosk mode"
    
    # Start Firefox
    firefox-esr "${KIOSK_URL}" "${@}" 2>&1 | tee -a "${LOG_FILE}" &
    FIREFOX_PID=$!
    export FIREFOX_PID
    
    # Wait for Firefox to fully load
    sleep 10
    
    # Activate fullscreen mode
    log_message "Activating fullscreen mode (F11)"
    xdotool search --sync --onlyvisible --class "Firefox" windowactivate key F11 2>&1 | tee -a "${LOG_FILE}" &
    FULLSCREEN_PID=$!
    export FULLSCREEN_PID
    
    # Set up periodic page refresh
    (
        while true; do
            sleep "${REFRESH_INTERVAL}"
            log_message "Refreshing page..."
            xdotool search --sync --onlyvisible --class "Firefox" windowactivate key F5 2>&1
        done
    ) | tee -a "${LOG_FILE}" &
    REFRESH_PID=$!
    export REFRESH_PID
    
    # Log process information
    log_message "Firefox kiosk initialized with PIDs:"
    log_message "- Firefox: ${FIREFOX_PID}"
    log_message "- Fullscreen: ${FULLSCREEN_PID}" 
    log_message "- Refresh: ${REFRESH_PID}"
    log_message "Type 'stop_firefox' to exit browser and script $(basename "$0")"
}

# Export functions for use in terminal
export -f log_message
export -f start_firefox
export -f stop_firefox

# Main execution
# Check if Firefox is already running and restart if it is
if pgrep firefox-esr >/dev/null; then
    log_message "Firefox already running, restarting..."
    stop_firefox
    sleep 2
    start_firefox "$@"
else
    start_firefox "$@"
fi
EOF

# Make the script executable
chmod +x "${SCRIPT_PATH}"
chown pi:pi "${SCRIPT_PATH}"

# Update systemd service to ensure proper permissions
SERVICE_PATH="/etc/systemd/system/firefox-kiosk.service"
cat > "${SERVICE_PATH}" << 'EOF'
[Unit]
Description=Firefox Kiosk Mode for AQI Monitor
After=network.target graphical.target
Conflicts=paqm-browser.service

[Service]
User=pi
Group=pi
Environment=DISPLAY=:0
WorkingDirectory=${PAQM_DIR}
ExecStart=${PAQM_DIR}/start_firefox_kiosk.sh
ExecStop=/bin/bash -c "pkill -f start_firefox_kiosk.sh; killall firefox-esr"
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=10
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd configuration
systemctl daemon-reload

# Restart the service
echo "Restarting Firefox kiosk service..."
systemctl restart firefox-kiosk.service

echo
echo "=============================="
echo "Firefox kiosk permissions fixed!"
echo
echo "Changes made:"
echo "- Updated script to use log file in: ${PAQM_DIR}/logs/"
echo "- Created and set permissions on logs directory"
echo "- Updated service file with proper permissions"
echo "- Restarted the service"
echo
echo "You can check the status with:"
echo "  sudo systemctl status firefox-kiosk.service"
echo
echo "You can view logs with:"
echo "  less ${PAQM_DIR}/logs/firefox-kiosk.log"
echo "=============================="

exit 0
