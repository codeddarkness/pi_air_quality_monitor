#!/usr/bin/env bash
# =============================================================================
# Firefox Kiosk Service Updater
# Updates the systemd service for the Firefox kiosk mode
# =============================================================================

set -e

# Configuration
SERVICE_FILE="/etc/systemd/system/firefox-kiosk.service"
BACKUP_FILE="${SERVICE_FILE}.bak.$(date +%Y%m%d%H%M%S)"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo or as root"
   exit 1
fi

echo "Updating Firefox Kiosk Service File"
echo "=================================="

# Create backup of existing service file
if [[ -f "${SERVICE_FILE}" ]]; then
    echo "Creating backup of existing service file..."
    cp "${SERVICE_FILE}" "${BACKUP_FILE}"
    echo "Backup created at: ${BACKUP_FILE}"
else
    echo "No existing service file found. Creating new one."
fi

# Create updated service file
echo "Creating updated service file..."
cat > "${SERVICE_FILE}" << 'EOF'
[Unit]
Description=Firefox Kiosk Mode for AQI Monitor
After=network.target graphical.target paqm.service
Conflicts=paqm-browser.service
PartOf=paqm.service

[Service]
User=pi
Environment=DISPLAY=:0
ExecStart=/home/pi/pi_air_quality_monitor/start_firefox_kiosk.sh
ExecStop=/bin/bash -c "pkill -f start_firefox_kiosk.sh; killall firefox-esr"
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=10
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Set proper permissions
chmod 644 "${SERVICE_FILE}"

# Reload systemd configuration
echo "Reloading systemd configuration..."
systemctl daemon-reload

# Enable the service
echo "Enabling Firefox kiosk service..."
systemctl enable firefox-kiosk.service

echo
echo "=================================="
echo "Firefox kiosk service updated successfully!"
echo "Service file: ${SERVICE_FILE}"
echo
echo "You can start the service with:"
echo "  sudo systemctl start firefox-kiosk.service"
echo
echo "You can check the status with:"
echo "  sudo systemctl status firefox-kiosk.service"
echo
echo "You can stop the service with:"
echo "  sudo systemctl stop firefox-kiosk.service"
echo "=================================="

exit 0
