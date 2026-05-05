#!/usr/bin/env bash
runlog=/home/pi/pi_air_quality_monitor/firefox-esr-run.log
DISPLAY=:0
export DISPLAY
function message(){
        echo -e "[ $(date) ] : ${@} "
}
export -f message
function stop_firefox(){
for background_pid in ${last_pid} ${refresh_pid} ${fullscreen_pid}; do
        if [[ -z "${background_pid}" ]] ; then
                continue
        fi
        if [[ -n "${background_pid}" ]] ; then
                kill ${background_pid} 2>/dev/null;
        else
                continue
        fi
done 2>/dev/null
killall firefox-esr 2>/dev/null
kill "$(ps -ef | grep start_firefox_kiosk.sh | grep -v grep | awk '{print $2}')" 2>/dev/null
for still_running in $(ps -ef | grep 'start_firefox_kiosk.sh\|firefox-esr' | grep -v 'log\|grep' | awk '{print $2}'); do
        if [[ -z "${still_running}" ]] ; then
                continue
        fi
        kill "${still_running}" 2>/dev/null && message "killed ${still_running}"
done 2>/dev/null
return
#return 0
}
function start_firefox(){
[[ -e "${runlog}" ]] && rm ${runlog}
message "starting firefox-esr" | tee ${runlog}
#DISPLAY=:0 firefox-esr --kiosk localhost:8000
DISPLAY=:0 firefox-esr localhost:8000 ${@} 2>&1 | tee -a ${runlog} &
last_pid=$!
export last_pid
sleep 10
message "trying F11 key" | tee -a ${runlog}
DISPLAY=:0 xdotool search --sync --onlyvisible --class "Firefox" windowactivate key F11 2>&1 | tee -a ${runlog} &
fullscreen_pid=$!
while true; do
        sleep 60
        clear
        message "refreshing..."
        DISPLAY=:0 xdotool search --sync --onlyvisible --class "Firefox" windowactivate key F5 2>&1
done | tee -a ${runlog} &
refresh_pid=$!
export last_pid fullscreen_pid refresh_pid
message "[last_pid:${last_pid}] [fullscreen_pid:${fullscreen_pid}] [refresh_pid:${refresh_pid}]"
message "type stop_firefox to exit browser and script ${BASH_SOURCE[0]}"
}
export -f start_firefox
export -f stop_firefox
if [[ -n "$(pgrep firefox-esr)" ]]; then
        stop_firefox
        start_firefox
else
        start_firefox
fi
