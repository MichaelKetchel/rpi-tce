#!/usr/bin/env bash
# set -e 

source ./common.sh

MNT_PATH="$WORK_PATH/mnt/"
BOOT_PATH="$MNT_PATH/boot"
DATA_PATH="$MNT_PATH/data"

sudo umount $BOOT_PATH
sudo umount $DATA_PATH

echo "Switching SD-MUX $SD_MUX_SERIAL back to TS"
sudo sd-mux-ctrl --device-serial=$SD_MUX_SERIAL --ts
# Naively wait 5 seconds for device to appear.
echo "Waiting for target ${TARGET_DEVICE}1 to appear..."

sleep 5
if [ -b "${TARGET_DEVICE}1" ]; then
    echo "Target device ${TARGET_DEVICE}1 found, mounting..."
    
    sudo mount -o rw ${TARGET_DEVICE}1 $BOOT_PATH
    sudo mount -o rw ${TARGET_DEVICE}2 $DATA_PATH
else
    echo "Target device unavailable or no first partition found. Doing nothing."
fi

