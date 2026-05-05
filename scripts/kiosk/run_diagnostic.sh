#!/bin/bash

# Firefox Kiosk Diagnostic Script

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Diagnostic report file
DIAG_REPORT="/tmp/firefox_kiosk_diagnostics.txt"

# Clear previous report
> "$DIAG_REPORT"

# Function to log and print diagnostic information
log_check() {
    local status="$1"
    local message="$2"
    local details="${3:-}"
    
    echo -e "$status $message" | tee -a "$DIAG_REPORT"
    if [[ -n "$details" ]]; then
        echo "$details" | tee -a "$DIAG_REPORT"
    fi
    echo "" | tee -a "$DIAG_REPORT"
}

# Diagnostic Checks
run_diagnostics() {
    echo "Firefox Kiosk Startup Diagnostic Report" | tee "$DIAG_REPORT"
    echo "Generated on $(date)" | tee -a "$DIAG_REPORT"
    echo "=================================" | tee -a "$DIAG_REPORT"
    echo "" | tee -a "$DIAG_REPORT"

    # 1. Check script permissions
    if [[ -f "/usr/local/bin/start_firefox_kiosk.sh" ]]; then
        SCRIPT_PERMS=$(ls -l "/usr/local/bin/start_firefox_kiosk.sh")
        if [[ -x "/usr/local/bin/start_firefox_kiosk.sh" ]]; then
            log_check "${GREEN}[PASS]${NC}" "Script permissions" "$SCRIPT_PERMS"
        else
            log_check "${RED}[FAIL]${NC}" "Script is not executable" "$SCRIPT_PERMS"
        fi
    else
        log_check "${RED}[FAIL]${NC}" "Script not found at /usr/local/bin/start_firefox_kiosk.sh"
    fi

    # 2. Check log file permissions
    if [[ ! -e "/var/log/firefox-esr-kiosk.log" ]]; then
        log_check "${YELLOW}[WARNING]${NC}" "Log file does not exist" "Attempting to create log file"
        sudo touch "/var/log/firefox-esr-kiosk.log"
        sudo chown pi:pi "/var/log/firefox-esr-kiosk.log"
        sudo chmod 664 "/var/log/firefox-esr-kiosk.log"
    fi

    LOGFILE_PERMS=$(ls -l "/var/log/firefox-esr-kiosk.log")
    log_check "${GREEN}[INFO]${NC}" "Log file permissions" "$LOGFILE_PERMS"

    # 3. Check X11 configuration
    log_check "${GREEN}[INFO]${NC}" "X11 Environment Check"
    echo "Current DISPLAY: $DISPLAY" | tee -a "$DIAG_REPORT"
    
    # Check X authority file
    X_AUTH_FILE="/home/pi/.Xauthority"
    if [[ -f "$X_AUTH_FILE" ]]; then
        log_check "${GREEN}[PASS]${NC}" "X Authority file exists" "$(ls -l "$X_AUTH_FILE")"
    else
        log_check "${RED}[FAIL]${NC}" "X Authority file missing" "Expected at $X_AUTH_FILE"
    fi

    # 4. Check Firefox installation
    if command -v firefox-esr &> /dev/null; then
        FIREFOX_VERSION=$(firefox-esr --version)
        log_check "${GREEN}[PASS]${NC}" "Firefox ESR installed" "$FIREFOX_VERSION"
    else
        log_check "${RED}[FAIL]${NC}" "Firefox ESR not installed"
    fi

    # 5. Check xdotool installation
    if command -v xdotool &> /dev/null; then
        XDOTOOL_VERSION=$(xdotool --version)
        log_check "${GREEN}[PASS]${NC}" "xdotool installed" "$XDOTOOL_VERSION"
    else
        log_check "${RED}[FAIL]${NC}" "xdotool not installed"
    fi

    # 6. Check Systemd service configuration
    if [[ -f "/etc/systemd/system/firefox-kiosk.service" ]]; then
        SERVICE_CONTENTS=$(cat "/etc/systemd/system/firefox-kiosk.service")
        log_check "${GREEN}[INFO]${NC}" "Systemd service file contents" "\n$SERVICE_CONTENTS"
    else
        log_check "${RED}[FAIL]${NC}" "Systemd service file missing"
    fi

    # 7. Check system journal for recent errors
    echo "Recent systemd journal entries:" | tee -a "$DIAG_REPORT"
    journalctl -u firefox-kiosk.service -n 20 | tee -a "$DIAG_REPORT"

    # Display report location
    echo -e "\n${GREEN}Diagnostic report saved to $DIAG_REPORT${NC}"
}

# Run diagnostics
run_diagnostics

# Optional: Open the report
read -p "Would you like to view the full diagnostic report? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cat "$DIAG_REPORT"
fi
