mkdir tools
cd tools/
wget https://mirrors.edge.kernel.org/pub/linux/utils/kernel/kexec/kexec-tools.tar.xz
unxz kexec-tools.tar.xz 
tar -xvf kexec-tools.tar 
cd kexec-tools-2.0.28/
tce-load -wi compiletc.tcz
./configure
make
sudo make install


# create package?

# export CFLAGS="-march=aarch64 -mtune=aarch64 -Os -pipe"
# export CXXFLAGS="-march=aarch64 -mtune=aarch64 -Os -pipe"
# export LDFLAGS="-Wl,-O1"

export CFLAGS="-Os -pipe"
export CXXFLAGS="-Os -pipe"
export LDFLAGS="-Wl,-O1"

tar xjvf package_name.tar.bz2
cd package_name
./configure --prefix=/usr/local
make -j5

touch /tmp/mark

make DESTDIR=/tmp/package install





# Additional packages needed on image:
parted.tcz
ruby.tcz
gdbm.tcz
ruby and deps







sudo mount /dev/mmcblk0p1 /mnt/mmcblk0p1/
sudo kexec --type zImage -l /mnt/mmcblk0p1/kernel8.img
sudo kexec --type zImage  --dtb=/mnt/mmcblk0p1/bcm2711-rpi-4-b.dtb --initrd=/mnt/mmcblk0p1/rootfs-piCore64-14.1.gz --command-line="console=serial0,115200 console=tty zswap.compressor=lz4 zswap.zpool=z3fold console=tty1 root=/dev/ram0 rootwait nortc loglevel=3 noembed" -e
sudo kexec --type zImage --dtb=/mnt/mmcblk0p1/bcm2711-rpi-4-b.dtb --initrd=/mnt/mmcblk0p1/initrd.gz --command-line="console=serial0,115200 console=tty zswap.compressor=lz4 zswap.zpool=z3fold console=tty1 root=/dev/ram0 rootwait nortc loglevel=3 noembed init=/sbin/init" -e


sudo mount /dev/mmcblk0p1 /mnt/mmcblk0p1/
sudo kexec --type zImage  --dtb=/mnt/mmcblk0p1/bcm2711-rpi-4-b.dtb --initrd=/mnt/mmcblk0p1/rootfs-piCore64-14.1.gz --command-line="console=serial0,115200 console=tty zswap.compressor=lz4 zswap.zpool=z3fold console=tty1 root=/dev/ram0 rootwait nortc loglevel=3 noembed" /mnt/mmcblk0p1/kernel8.img

cd /mnt/mmcblk0p1
sudo cat rootfs-piCore64-14.1.gz modules-6.1.77-piCore-v8+.gz > initrd.gz


sudo mkdir /mnt/boot
sudo mkdir /mnt/rootfs
sudo mount /dev/sda1 /mnt/boot
sudo mount /dev/sda2 /mnt/rootfs
sudo kexec --type zImage -l /mnt/boot/kernel8.img
sudo kexec --type zImage --dtb /mnt/boot/bcm2711-rpi-4-b.dtb --command-line "$(cat /mnt/boot/cmdline.txt) init=/sbin/init debug rootwait root=/dev/sda2 rootfstype=ext4" -e


sudo mkdir /mnt/boot
sudo mkdir /mnt/rootfs
sudo mount /dev/sda1 /mnt/boot
sudo mount /dev/sda2 /mnt/rootfs
# sudo kexec --type zImage --dtb /mnt/boot/bcm2711-rpi-4-b.dtb --command-line "$(cat /mnt/boot/cmdline.txt) init=/sbin/init debug rootwait root=/dev/sda2 rootfstype=ext4" -l /mnt/boot/kernel8.img
sudo kexec -a -x --type zImage --dtb /mnt/boot/bcm2711-rpi-4-b.dtb --command-line "$(cat /mnt/boot/cmdline.txt) init=/sbin/init debug rootwait root=/dev/sda2 rootfstype=ext4" -l /mnt/boot/kernel8.img
sudo kexec -e 
OR sudo reboot?
# sudo kexec -e  --dtb bcm2711-rpi-4-b.dtb --command-line "console=serial0,115200 console=tty1 root=PARTUUID=6b044db4-02 rootfstype=ext4 fsck.repair=yes rootwait"


# $(cat /mnt/boot/cmdline.txt)

https://forums.raspberrypi.com/viewtopic.php?t=243995&start=275






sudo udhcpc -i eth0 -x hostname:box -V RGNETS -O 66 -f
sudo mkdir /usr/share/udhcpc/default.script.d/


#!/bin/sh

# udhcpc script edited by Tim Riker <Tim@Rikers.org>

[ -z "$1" ] && echo "Error: should be called from udhcpc" && exit 1

RESOLV_CONF="/etc/resolv.conf"
[ -n "$broadcast" ] && BROADCAST="broadcast $broadcast"
[ -n "$subnet" ] && NETMASK="netmask $subnet"

case "$1" in
        deconfig)
                /sbin/ifconfig $interface 0.0.0.0
                ;;

        renew|bound)
                /sbin/ifconfig $interface $ip $BROADCAST $NETMASK

                if [ -n "$router" ] ; then
                        echo "deleting routers"
                        while route del default gw 0.0.0.0 dev $interface ; do
                                :
                        done

                        metric=0
                        for i in $router ; do
                                route add default gw $i dev $interface metric $((metric++))
                        done
                fi

                echo -n > $RESOLV_CONF
                [ -n "$domain" ] && echo search $domain >> $RESOLV_CONF
                for i in $dns ; do
                        echo adding dns $i
                        echo nameserver $i >> $RESOLV_CONF
                done
                if [ -n "$ntpsrv" ]; then
                        cat /proc/cmdline | grep -q ntpserver
                        if [ $? -eq 0 ]; then
                                echo "cmdline overriding dhcp ntpserver setting"
                        else
                                echo "adding ntpserver"
                                echo $ntpsrv > /etc/sysconfig/ntpserver
                        fi
                fi
                ;;
esac

exit 0
