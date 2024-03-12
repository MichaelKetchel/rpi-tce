#!/usr/bin/env bash
# set -e 
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
KERNEL_VERSION="6.1.77"
SOURCES_PATH="$SCRIPT_PATH/sources"
KERNEL_SOURCE_PATH="$SCRIPT_PATH/linux"
ARTIFACTS_PATH="$SCRIPT_PATH/artifacts"
CORE_COUNT=$(cat /proc/cpuinfo | grep processor | wc -l)
# tar -C kernel_source/ -xvf sources/rpi-linux-6.1.68.tar.xz 
# git clone --depth=1 --branch rpi-6.1.y https://github.com/raspberrypi/linux

KERNEL_SOURCE_COMMIT_HASH="c0169f2c1"

KERNEL=kernel8
CONFIG_LOCALVERSION="-piCore-v8"
KERNEL_NAME="${KERNEL_VERSION}-piCore-v8+"

cd $KERNEL_SOURCE_PATH
# git reset --hard HEAD
# git clean -f 

# patch -Np1 -i ../patches/squashfs-warning.patch
# patch -Np1 -i ../patches/logo.patch


# make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2711_defconfig

# # CONFIG_LOCALVERSION="-piCore-rgnets-v8"

# xz -fkd $SOURCES_PATH/6.1.68-piCore-v8_.config.xz
# cp $SOURCES_PATH/6.1.68-piCore-v8_.config $KERNEL_SOURCE_PATH/.config

# cat <<EOT >> $KERNEL_SOURCE_PATH/.config
# CONFIG_KEXEC=y
# CONFIG_KEXEC_FILE=y
# EOT

# make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

mkdir -p $ARTIFACTS_PATH
sudo make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=$ARTIFACTS_PATH/built_modules modules_install
sudo mkdir -p $ARTIFACTS_PATH/boot/overlays
sudo cp arch/arm64/boot/dts/broadcom/*.dtb $ARTIFACTS_PATH/boot/
sudo cp arch/arm64/boot/dts/overlays/*.dtb* $ARTIFACTS_PATH/boot/overlays/
sudo cp arch/arm64/boot/dts/overlays/README $ARTIFACTS_PATH/boot/overlays/
sudo cp arch/arm64/boot/Image $ARTIFACTS_PATH/boot/$KERNEL.img

# depmod -a -b /tmp/extract 5.4.51-piCore-v7
# depmod -a -b built_modules/ -E linux/Module.symvers -F linux/System.map 6.1.68-piCore-v8
sudo depmod -a -b $ARTIFACTS_PATH/built_modules/ -E $KERNEL_SOURCE_PATH/Module.symvers -F $KERNEL_SOURCE_PATH/System.map "${KERNEL_NAME}"
#  depmod -a -b built_modules/ -E linux/Module.symvers -F linux/System.map -o artifacts  '6.1.77-piCore-v8+'


# Prepare modules for packaging
sudo mkdir -p $ARTIFACTS_PATH/built_modules/lib/modules/$KERNEL_NAME/kernel.tclocal
sudo mkdir -p $ARTIFACTS_PATH/built_modules/usr/local/lib/modules/$KERNEL_NAME/kernel/

# Pack modules
cd $ARTIFACTS_PATH/built_modules/
sudo find | sudo cpio -o -H newc | gzip -2 > ../modules-$KERNEL_NAME.gz