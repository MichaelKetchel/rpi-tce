#!/usr/bin/env bash
set -e
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
source $SCRIPT_PATH/common.sh
cd $PROJECT_PATH

docker build -t rpi-tce-builder docker/builder/
docker run --privileged -v /dev:/dev  -v./:/mnt  rpi-tce-builder ./scripts/build_image.sh