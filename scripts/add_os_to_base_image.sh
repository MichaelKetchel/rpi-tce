#!/usr/bin/env bash

set -e
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
source $SCRIPT_PATH/common.sh
cd $PROJECT_PATH

MNT_PATH="$WORK_PATH/mnt/"
BOOT_PATH="$MNT_PATH/boot"
DATA_PATH="$MNT_PATH/data"


ADDON_IMAGE_PATH=$1
# Get the file name without extension from ADDON_IMAGE_PATH
ADDON_IMAGE_FILENAME=$(basename -- "$ADDON_IMAGE_PATH")
ADDON_IMAGE_NAME=${ADDON_IMAGE_FILENAME%.img}

# Get the size of the file at ADDON_IMAGE_PATH and store it in a variable
ADDON_IMAGE_SIZE=$(stat -c%s "$ADDON_IMAGE_PATH")
echo "The size of $ADDON_IMAGE_NAME is: $ADDON_IMAGE_SIZE bytes"

NEW_IMAGE_PATH=$WORK_PATH/${NEW_IMAGE_NAME}-${ADDON_IMAGE_NAME}.img
BASE_IMAGE_PATH=$WORK_PATH/$NEW_IMAGE_NAME.img

echo "Copying base image from $BASE_IMAGE_PATH to work with"
cp $BASE_IMAGE_PATH $NEW_IMAGE_PATH

echo "Extending base image to an additional $ADDON_IMAGE_SIZE"
dd if=/dev/zero bs=$ADDON_IMAGE_SIZE count=1 >> $NEW_IMAGE_PATH

# Get the size of the ADDON_IMAGE_PATH and store it in a variable



echo $NEW_IMAGE_PATH
