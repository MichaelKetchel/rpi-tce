tce-load -i compiletc bash perl5 bc ncurses-dev openssl-dev

git clone --depth=1 --branch rpi-5.4.y https://github.com/raspberrypi/linux

cd linux

patch -Np1 -i ../squashfs-warning.patch

CFLAGS="-mcpu=cortex-a7"
KERNEL=kernel7
make bcm2709_defconfig

CONFIG_LOCALVERSION="-piCore-v7"
make oldconfig
make zImage modules dtbs [3h 25m 55s]


sudo make modules_install [DEPMOD  5.4.51-piCore-v7]

sudo cp arch/arm/boot/dts/*.dtb /boot/
sudo cp arch/arm/boot/dts/overlays/*.dtb* /boot/overlays/
sudo cp arch/arm/boot/dts/overlays/README /boot/overlays/
sudo cp arch/arm/boot/zImage /boot/$KERNEL.img

[edit modules]
sudo depmod -a -b /tmp/extract 5.4.51-piCore-v7