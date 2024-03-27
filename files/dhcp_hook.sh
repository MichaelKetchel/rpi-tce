#!/bin/sh
[ -z "$1" ] && echo "Error: should be called from udhcpc" && exit 1
echo "Running RG Nets DHCP hooks..."
OPTIONS_FILE="/tmp/dhcp_config.yml"
case "$1" in
    deconfig)
            rm $OPTIONS_FILE
            ;;

    renew|bound)
            echo "$interface:" >> $OPTIONS_FILE
            echo "  ip: $ip" >> $OPTIONS_FILE
            echo "  broadcast: $broadcast" >> $OPTIONS_FILE
            echo "  netmask: $subnet" >> $OPTIONS_FILE
            echo "  routers: " >> $OPTIONS_FILE
            for i in $router ; do
                echo "    - $i" >> $OPTIONS_FILE
            done
            echo "  domain: $domain" >> $OPTIONS_FILE
            echo "  dns:" >> $OPTIONS_FILE
            for i in $dns ; do
                echo "    - $i" >> $OPTIONS_FILE
            done
            echo "  ntp: $ntpsrv" >> $OPTIONS_FILE
            echo "  opts:" >> $OPTIONS_FILE

            for i in $(seq 0 255) ; do
                optvar=opt$i
                val=$(eval echo \$$optvar)
                if [ "$val" ]; then
                    echo "    $i: $val" >> $OPTIONS_FILE
                fi
            done
            ;;
esac

exit 0