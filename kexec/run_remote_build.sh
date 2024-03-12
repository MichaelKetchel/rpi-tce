#!/usr/bin/env bash
set -e
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
SSH_ADDRESS="tc@192.170.1.53"
cd $SCRIPT_PATH
scp ./package-kexec.sh $SSH_ADDRESS:~/
ssh $SSH_ADDRESS -t 'rm -rf /tmp/kexec*'
ssh $SSH_ADDRESS -t 'sh -lc "~/package-kexec.sh"'
mkdir -p artifacts
scp $SSH_ADDRESS:/tmp/kexec_package/kexec_package.tcz.list ./artifacts/
scp $SSH_ADDRESS:/tmp/kexec_package.tcz ./artifacts/
