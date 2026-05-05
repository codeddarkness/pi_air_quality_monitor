#!/usr/bin/env bash
## SET CH340 SENSOR TO TTYUSB0 

(return 0 2>/dev/null) && sourced=1 || sourced=0

function show_reference_info(){
cat <<EUSB
# LOCAL USB BUS DATA : lsusb
Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 001 Device 009: ID 1a86:7523 QinHeng Electronics CH340 serial converter
Bus 001 Device 010: ID 046d:c52b Logitech, Inc. Unifying Receiver
Bus 001 Device 002: ID 2109:3431 VIA Labs, Inc. Hub
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub

EUSB

cat <<EOREF
# REFERENCE USB MAPPING
Bus 001 Device 004: ID 0403:6001 Future Technology Devices International
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", SYMLINK+="myUSB"
sudo nano /etc/udev/rules.d/99_usbdevices.rules

EOREF

cat <<ECAT
# appending to file with sudo
echo 'deb blah ... blah' | sudo tee -a /etc/apt/sources.list > /dev/null

ECAT
}

function update_dev_rules(){
sys_file=/etc/udev/rules.d/99_usbdevices.rules
usb_ref='SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", SYMLINK+="myUSB"'

if [[ -z "$(grep -o "${usb_ref}" "${sys_file}")" ]]; then
	echo "${usb_ref}" | sudo tee ${sys_file} > /dev/null
	cat "${sys_file}" && echo " - ${sys_file} created"
else
	echo " - ${sys_file} exists" && cat "${sys_file}"
fi
}

if [[ "${sourced}" -eq 0 ]]; then
	source "$(realpath "${BASH_SOURCE[0]}")"
else

if [[ "${1}" == -ref* ]] ; then
	export -f show_reference_info && echo " - function loaded : show_reference_info"
elif [[ "${1}" == -load* ]]; then
	export -f update_dev_rules && echo " - function loaded : update_dev_rules"
else
	update_dev_rules
fi
fi
