#!/usr/bin/env bash
# set -e 

# This is a helper script to leverage a second Pi with an Inland 4 relay pi HAT to control the power and flash pins on a CM4 IO board.
# The power for the pi should be on the normally closed contacts on relay 1 (pin 4), and the flash pins should be on the normally
# open contacts on relay 2 (pin 22).

# CM4_SERIAL_ID is the ID string found in the udevadm info output found for the cm4 board when it's in flash mode post 'rpiusbboot'.
# Using this to find the device avoids the risk of accidentally writing to the wrong device by assuming a fixed device.
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
source $SCRIPT_PATH/common.sh
cd $PROJECT_PATH
SSH_ADDRESS="mdk@flashpi.local"


# Relay pins on [4, 22, 6, 26]

CM4_SERIAL_ID="ID_USB_SERIAL=RPi-MSD-_0001_9a18329a-0:0"

# power cycle the CM4 board into flash mode.
cm4_set_flash () {
    echo "Switching CM4 to flash"
    [[ "$@" ]] && echo "options: $@"
    # Power off (relay high), sleep, then Flash Jumper on (relay high), then power back on
    ssh $SSH_ADDRESS -t 'sh -lc "pinctrl set 4 op pn dh ; sleep 1; pinctrl set 22 op pn dh; sleep 1; pinctrl set 4 op pn dl"'
    sudo rpiusbboot
}

# Power cycle the CM4 board into boot mode
cm4_set_boot () {
    echo "Booting CM4"
    [[ "$@" ]] && echo "options: $@"
    # Power off (relay high), sleep, then Flash Jumper off (relay high), then power back on
    ssh $SSH_ADDRESS -t 'sh -lc "pinctrl set 4 op pn dh ; sleep 1; pinctrl set 22 op pn dl; sleep 1; pinctrl set 4 op pn dl"'
}


cm4_do_flash () {
    cm4_set_flash
    sleep 5
    
    cm4_flash_only "$@"

    sync
    sleep 1
    cm4_set_boot
    # echo "$CM4_DEV"
}

# Work this in? https://www.cyberciti.biz/faq/linux-unix-dd-command-show-progress-while-coping/
# Only do the flash. This assumes you've already run 'rpiusbboot' and plugged in the pi.
cm4_flash_only () {
    CM4_DEV=$(find /dev -regex '/dev/sd.' | xargs -I % bash -c "udevadm info % | grep -q '$CM4_SERIAL_ID' && echo %")
    echo "sudo dd if=$1 of=$CM4_DEV bs=8M status=progress"
    sudo dd if=$1 of="$CM4_DEV" bs=8M status=progress
    sync
}

case $1 in
    cm4_set_flash) "$@"; exit;;
    cm4_set_boot) "$@"; exit;;
    cm4_do_flash) "$@"; exit;;
    cm4_flash_only) "$@"; exit;;
esac
