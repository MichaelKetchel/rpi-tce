#!/usr/bin/env bash
# set -e 
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
PROJECT_PATH="$SCRIPT_PATH/.."
WORK_PATH="$PROJECT_PATH/work"
SOURCES_PATH="$PROJECT_PATH/sources"
NEW_IMAGE_NAME="rg-piCore64"
SD_MUX_SERIAL='bdgrd_sdwirec_101'
TARGET_DEVICE=/dev/sdc


print_title() {
    echo ""
    echo -e '\033[1;30m'"$1"'\033[0m'
}