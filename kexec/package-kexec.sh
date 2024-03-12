#!/usr/bin/env sh

set -e
# tce-load -wi compiletc.tcz
# tce-load -wi squashfs-tools.tcz
export CFLAGS="-Os -pipe"
export CXXFLAGS="-Os -pipe"
export LDFLAGS="-Wl,-O1"

PKG_NAME=kexec_package
PKG_OUTPUT_DIR=/tmp/$PKG_NAME

CORE_COUNT=$(cat /proc/cpuinfo | grep processor | wc -l)

touch /tmp/mark

BUILD_DIR=/tmp/kexec_build
mkdir -p $BUILD_DIR
mkdir -p $PKG_OUTPUT_DIR

cd $BUILD_DIR
wget -nc https://mirrors.edge.kernel.org/pub/linux/utils/kernel/kexec/kexec-tools.tar.xz
unxz kexec-tools.tar.xz 
tar -xvf kexec-tools.tar
cd kexec-tools-2.0.28/
./configure --prefix=/usr/local
make -j$(( $CORE_COUNT + 1 ))

make DESTDIR=$PKG_OUTPUT_DIR install

# Strip debug info
# find . | xargs file | grep "executable" | grep ELF | grep "not stripped" | cut -f 1 -d : | xargs strip --strip-unneeded 2> /dev/null || find . | xargs file | grep "shared object" | grep ELF | grep "not stripped" | cut -f 1 -d : | xargs strip -g 2> /dev/null

cd $PKG_OUTPUT_DIR/..
mksquashfs $PKG_NAME $PKG_NAME.tcz
cd $PKG_OUTPUT_DIR
find usr -not -type d > $PKG_NAME.tcz.list
rm -rf usr