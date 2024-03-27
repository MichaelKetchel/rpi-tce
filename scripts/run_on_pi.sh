#!/usr/bin/env bash
set -e
SCRIPT_NAME=$0
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
source $SCRIPT_PATH/common.sh
cd $PROJECT_PATH

SSH_ADDRESS=$1
cd $PROJECT_PATH


print_usage() {
echo "Usage:
    boot <ssh_address>: Runs ./files/boot_script.sh on host
    dhcp <ssh_address>: Runs udhcp with ./files/dhcp_hook.sh on host
    setup <ssh_address>: Tries to automatically setup host for ssh access
    ssh <ssh_address>: Connects to host via ssh. Accepts additional SSH arguments
    connect: Alias of ssh

    Example: run_on_pi.sh tc@192.170.1.55 dhcp
"
}

setup () {
    ssh-keygen -R $(sed 's|[^@]*@||' <<< $SSH_ADDRESS)
    IFS='@' read -ra address_parts <<< "$SSH_ADDRESS"

    if ! command -v sshpass &> /dev/null; then
        ssh-copy-id $SSH_ADDRESS
    else
        echo "User extracted from address: ${address_parts[0]}"
        case ${address_parts[0]} in
            tc) sshpass -p piCore ssh-copy-id $SSH_ADDRESS ;;
            pi|*) sshpass -p raspberry ssh-copy-id $SSH_ADDRESS ;;
        esac
    fi
}

do_ssh () {
    # shift;
    ssh $SSH_ADDRESS "$@"
}

boot () {
    # scp ./rebootp/rebootp $SSH_ADDRESS:~/
    scp ./files/boot_script.rb $SSH_ADDRESS:~/bootscript
    # ssh $SSH_ADDRESS -t 'sh -lc "filetool.sh -b"'
    ssh $SSH_ADDRESS -t 'sh -lc "sudo ~/bootscript"'
}

dhcp () {
    # scp ./rebootp/rebootp $SSH_ADDRESS:~/
    scp ./files/dhcp_hook.sh $SSH_ADDRESS:~/dhcp_hook.sh
    # ssh $SSH_ADDRESS -t 'sh -lc "filetool.sh -b"'
    ssh $SSH_ADDRESS -t 'sh -lc "chmod +x ~/dhcp_hook.sh; sudo udhcpc -i eth0 -x hostname:box -V \"RG Nets\" -O 43 -fqs ~/dhcp_hook.sh "'
    ssh $SSH_ADDRESS -t 'sh -lc "cat /tmp/dhcp_config.yml"'
}


if [[ $# -eq 0 ]] ; then
    echo "Missing arguments"
    print_usage
    exit 1
fi
shift
case $1 in
    setup) "$@"; exit;;
    ssh|connect) shift; do_ssh "$@"; exit;;
    boot) "$@"; exit;;
    dhcp) "$@"; exit;;
    *) echo "Unrecognized arguments: $@"; print_usage; exit
    ;;
esac

