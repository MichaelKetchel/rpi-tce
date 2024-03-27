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

    Example: run_on_pi.sh tc@192.170.1.55 dhcp
"
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
    boot) "$@"; exit;;
    dhcp) "$@"; exit;;
    *) echo "Unrecognized arguments: $@"; print_usage; exit
    ;;
esac

