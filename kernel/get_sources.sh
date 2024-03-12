#!/usr/bin/env bash
set -e 
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)

KERNEL_VERSION="6.1.68"
SOURCE_BASE_URL="http://tinycorelinux.net/14.x/aarch64/releases/RPi/src/kernel/"
SOURCE_FILES=($(curl --silent $SOURCE_BASE_URL| grep -o 'href=".*">' | sed 's/href="//;s/">//' | grep -v '../' | grep "$KERNEL_VERSION"))

SOURCE_PATH="$SCRIPT_PATH/sources/"
mkdir -p $SOURCE_PATH
cd $SOURCE_PATH

for file in "${SOURCE_FILES[@]}"; do
    file_url="${SOURCE_BASE_URL}${file}"
    # echo "Getting ${file_url}"
    wget -nc $file_url
done

# Get patches

PATCH_BASE_URL="http://www.tinycorelinux.net/14.x/x86/release/src/kernel/6.1-patches/"
PATCH_FILES=($(curl --silent $PATCH_BASE_URL| grep -o 'href=".*">' | sed 's/href="//;s/">//' | grep -v '../'))
PATCH_PATH="$SCRIPT_PATH/patches/"
mkdir -p $PATCH_PATH
cd $PATCH_PATH
for file in "${PATCH_FILES[@]}"; do
    file_url="${PATCH_BASE_URL}${file}"
    # echo "Getting ${file_url}"
    wget -nc $file_url
done

