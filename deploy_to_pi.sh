#!/usr/bin/env bash
# set -e 
source common.sh

echo "Switching SD-MUX $SD_MUX_SERIAL back to TS"
sudo sd-mux-ctrl --device-serial=$SD_MUX_SERIAL --ts
# Naively wait 5 seconds for device to appear.
echo "Waiting for target ${TARGET_DEVICE}1 to appear..."

sleep 5
if [ -b "${TARGET_DEVICE}1" ]; then
    echo "Target device ${TARGET_DEVICE}1 found, writing..."
    sudo dd if="$WORK_PATH/$NEW_IMAGE_NAME.img" of=$TARGET_DEVICE bs=4M status=progress
    echo "Switching SD-MUX $SD_MUX_SERIAL back to DUT"
    sudo sd-mux-ctrl --device-serial=$SD_MUX_SERIAL --dut
else
    echo "Target device unavailable or no first partition found. Doing nothing."
fi
