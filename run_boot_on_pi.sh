#!/usr/bin/env bash
set -e
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)

SSH_ADDRESS="tc@192.170.1.54"
cd $SCRIPT_PATH
scp ./files/boot_script.sh $SSH_ADDRESS:~/
ssh $SSH_ADDRESS -t 'sh -lc "~/boot_script.sh"'
