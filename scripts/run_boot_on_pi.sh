#!/usr/bin/env bash
set -e
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
source $SCRIPT_PATH/common.sh
cd $PROJECT_PATH

SSH_ADDRESS="tc@192.170.1.55"
cd $PROJECT_PATH
# scp ./rebootp/rebootp $SSH_ADDRESS:~/
scp ./files/boot_script.rb $SSH_ADDRESS:~/bootscript
# ssh $SSH_ADDRESS -t 'sh -lc "filetool.sh -b"'
ssh $SSH_ADDRESS -t 'sh -lc "sudo ~/bootscript"'