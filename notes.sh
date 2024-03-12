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